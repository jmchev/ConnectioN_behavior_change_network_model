#### Agent-based Network Model for Health Behavior ####

library(parallel)
library(data.table)
library(pbapply)

# Source scripts with required functions

source("Construct_synthetic_networks.R")

source("SIHR_Network_Function.R")

source("Network_model_parallel_function.R")

# Load XGBoost model 

xg_behavior_model <- readRDS("xg_behavior_model.rds")

# for baseline results (awareness, behavior, fatigue, readopt, and gate parameters 
# should all be set to FALSE)
param_df<- read.csv("baseline_param_df.csv")


# for behavior scenario results and sensitivity analysis
param_df<- read.csv("behavior_param_df.csv")

################################################################################

# Initialize empty results data frames

sihr_sim_output_behavior<- data.table()

node_sim_output_behavior<- data.table()

# Networks list
networks<- list("Preferential attachment (10)"= pa,
                "Random (10)" = r,
                "Small world (10)" = sw,
                "Small world (10, WTI=5)"= sw_wti_5,
                "Small world (10, WTI=1)"= sw_wti_1,
                "Small world (10, PS=7)"= sw_ps_7,
                "Small world (10, PS=1)"= sw_ps_1,
                "Small world (10, WTI=5, PS=7)"= sw_all_57,
                "Small world (10, WTI=3, PS=4)"= sw_all_34,
                "Small world (10, WTI=1, PS=1)"= sw_all_1
)

for(q in 1:nrow(param_df_5)){
  
  params<- param_df
  
  # Assign network type
  network_idx <- params$network[q]
  network <- networks[[network_idx]]
  network_name <- network_idx
  
  # Assign parameters
  
  timesteps <- 1500
  infection_prob <- params$infection_prob[q]
  recovery_time_I <- 10
  cumulative_hosp_prob<- 0.01
  hosp_prob <- params$hosp_prob[q]
  recovery_time_H <- 15
  mu<-0.53
  alpha_aware<-params$alpha_aware[q]
  beta_aware<-params$beta_aware[q]
  fatigue_shape<-params$fatigue_shape[q]
  fatigue_scale<-params$fatigue_scale[q]
  alpha_hosp<-params$alpha_hosp[q]
  beta_hosp<-params$beta_hosp[q]
  hosp_window<- 7
  hosp_threshold<- 0.05
  awareness<- T
  behavior<- T
  fatigue<- T
  readopt<- T
  gate<- T
  threshold<- F
  voi<-  strsplit(params$voi[q], ",")[[1]] #c("age", "gender", "hospital_occupancy_per_100k", "perc_severe", "willing_to_isolate", "working_outside_home")
  scaling_factor<- 100
  
  
  # Compute network centralities
  sim_centralities<-
    data.table( 
      nodes=V(network),
      degree=degree(network),
      eigenvector=eigen_centrality(network)$vector,
      betweenness=betweenness(network, normalized = T),
      closeness=closeness(network, normalized = T)
    )
  
  # Model and parameter setup
  
  # Assign initial model states and variables
  V(network)$state <- "S"  # All start susceptible
  V(network)$aware <- 0
  V(network)$behavior <- 0
  V(network)$days_infected <- 0
  V(network)$days_hospitalized <- 0
  V(network)$days_behavior <- 0
  V(network)$fatigue_time <- NA_integer_
  V(network)$days_abandoned <- NA_integer_
  V(network)$time_infected <- NA_integer_
  V(network)$closeness_at_infection <- NA
  V(network)$degree_at_infection <- NA
  V(network)$time_aware <- NA_integer_
  V(network)$time_behavior <- NA_integer_
  V(network)$ever_behavior <- 0L
  V(network)$total_days_behavior <-  NA_integer_
  V(network)$total_days_abandoned <-  NA_integer_
  V(network)$behavior_at_infection <-  NA_integer_
  V(network)$hospitalizations_at_behavior <-  NA_integer_
  V(network)$fist_abandoned <-  NA_integer_
  V(network)$times_adopted <-  NA_integer_
  V(network)$times_abandoned <-  NA_integer_
  
  # Additional model parameters
  n<-vcount(network)
  
  # Model params list for import into functons
  model_params<- list(n,
                      timesteps,
                      infection_prob,
                      hosp_prob, 
                      recovery_time_I,
                      recovery_time_H,
                      mu,
                      alpha_aware,
                      beta_aware,
                      fatigue_shape,
                      fatigue_scale,       #NUMERIC: choose how many starting infections
                      alpha_hosp,
                      beta_hosp,
                      hosp_window,
                      hosp_threshold,
                      awareness,
                      behavior,
                      fatigue,
                      readopt,
                      gate,
                      threshold,
                      voi,
                      scaling_factor)
  
  
  # create cluster with 10 cores (12 cores total, 8 performance, 4 efficiency)
  cl <- makeCluster(parallel::detectCores() - 2)
  
  # export everything the function needs to each core
  clusterExport(cl, c("network", "model_params", "first_infected", "starting_infections", "sim_centralities", 
                      "xg_behavior_model","run_sihr_network", "run_model_functon"))
  
  clusterEvalQ(cl, {
    library(igraph)
    library(data.table)
    library(xgboost)
    library(tidyverse)
    library(Matrix)
    library(naniar)
    library(truncnorm)
    library(readr)
  })
  
  # set cluster seed
  clusterSetRNGStream(cl, iseed = 123)
  
  
  sim_results <- pblapply(1:100, function(k){
    run_model_functon(k, network, first_infected, starting_infections, sim_centralities, model_params)
  }, cl = cl)
  
  
  # stop cluster
  stopCluster(cl)
  
  # extract results
  sihr_sim_output <- rbindlist(lapply(sim_results, function(x) x[[1]]))
  node_sim_output <- rbindlist(lapply(sim_results, function(x) x[[2]]))
  
  
  sihr_sim_output_behavior<- 
    rbindlist(list(sihr_sim_output_behavior, sihr_sim_output[ ,`:=`(network=network_name,
                                                                    trans_prob=paste0(infection_prob),
                                                                    aware_parms=paste0(alpha_aware,",", beta_aware),
                                                                    fatigue_parms=paste0(fatigue_shape,",",fatigue_scale),
                                                                    hosp_parms=paste0(alpha_hosp,",", beta_hosp),
                                                                    hosp_prob=paste0(hosp_prob),
                                                                    voi=params$voi[q]
    )]))
  
  node_sim_output_behavior<- 
    rbindlist(list(node_sim_output_behavior, node_sim_output[ ,`:=`(network=network_name,
                                                                    trans_prob=paste0(infection_prob),
                                                                    aware_parms=paste0(alpha_aware,",", beta_aware),
                                                                    fatigue_parms=paste0(fatigue_shape,",",fatigue_scale),
                                                                    hosp_parms=paste0(alpha_hosp,",", beta_hosp),
                                                                    hosp_prob=paste0(hosp_prob),
                                                                    voi=params$voi[q]
    )]))
  
}
