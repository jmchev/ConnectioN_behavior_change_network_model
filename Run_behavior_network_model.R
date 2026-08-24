#### Agent-based Network Model for Health Behavior ####

library(parallel)
library(data.table)
library(pbapply)

# Source scripts with required functions

setwd("...")

source("SIHR_Network_Function.R")

source("Network_model_parallel_function.R")

# Load synthetic networks 

load("Synthetic_network_data.RData")

# Load XGBoost model 

xg_behavior_model <- readRDS("xg_behavior_model.rds")



################################################################################

# Initialize empty results data frames

# sihr_sim_output_behavior<- data.table()

# node_sim_output_behavior<- data.table()

# Networks list
networks<- list("Preferential attachment"= pa,
                "Random" = r,
                "Small world" = sw)

# MODEL PARAMETERS
timesteps <- 1500
infection_prob <- 0.0328
recovery_time_I <- 10
cumulative_hosp_prob<- 0.01
hosp_prob <- (1-exp(-0.008)) # 1 - (1 - cumulative_hosp_prob)^(1/recovery_time_I)
recovery_time_H <- 15 # 24
mu<-0.53
alpha_aware<-15
beta_aware<-0.55
fatigue_shape<-2.34
fatigue_scale<-43.46
alpha_hosp<-13
beta_hosp<-0.50
hosp_window<- 7
hosp_threshold<- 0.05
awareness<- T
behavior<- T
fatigue<- T
readopt<- T
gate<- T
threshold<- F
voi<- c("age", "gender", "hospital_occupancy_per_100k", "perc_severe", "willing_to_isolate", "working_outside_home")
scaling_factor<- 100  #necessary to normalize hospitalization rate to range recognized by XGBoost function


first_infected="random"    #OPTIONS: "random", "degree", "eigenvector", "betweenness", "closeness"
starting_infections=2        #NUMERIC: choose how many starting infections 


# Model loop for network types (NOTE: ensure parameters are initialized)

sihr_sim_output_behavior<- data.table()

node_sim_output_behavior<- data.table()


for(q in seq_along(networks)){
  
  # Assign network type
  network<- networks[[q]]
  
  #network<- sw
  
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
                      fatigue_scale,      
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
    rbindlist(list(sihr_sim_output_behavior, sihr_sim_output[ ,`:=`(network=paste0(names(networks)[q]),
                                                                    aware_parms=paste0(alpha_aware,",", beta_aware),
                                                                    fatigue_parms=paste0(fatigue_shape,",",fatigue_scale),
                                                                    hosp_parms=paste0(alpha_hosp,",", beta_hosp)
                                                                    )]))
  
  node_sim_output_behavior<- 
    rbindlist(list(node_sim_output_behavior, node_sim_output[ ,`:=`(network=paste0(names(networks)[q]),
                                                                    aware_parms=paste0(alpha_aware,",", beta_aware),
                                                                    fatigue_parms=paste0(fatigue_shape,",",fatigue_scale),
                                                                    hosp_parms=paste0(alpha_hosp,",", beta_hosp)
                                                                    )]))

}




behavior_results_v14<- list(sihr_sim_output_behavior, node_sim_output_behavior)

save(behavior_results_v14, file="behavior_results_v14_03July2026.RData")



behavior_results_v9 <- list(sihr_sim_output_behavior, node_sim_output_behavior)


save(behavior_results_v9, file="behavior_results_v9_25June2026.RData")






