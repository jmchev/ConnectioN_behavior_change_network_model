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



################################################################################

# Initialize empty results data frames

sihr_sim_output_behavior<- data.table()

node_sim_output_behavior<- data.table()

# Networks list
networks<- list("Preferential attachment"= pa,
                "Random" = r,
                "Small world" = sw)

# MODEL PARAMETERS
timesteps <- 1500             # time steps in days 
infection_prob <- 0.0328      # transmission probability per contact per day
recovery_time_I <- 10.        # length of infectiousness period
hosp_prob <- (1-exp(-0.008))  # hospitalization probability per day
recovery_time_H <- 15         # length of time in hospital (fully isolated)
mu<-0.53                      # proportion of edges kept when practicing social distancing
alpha_aware<-15               # logistic function alpha parameter for awareness function (slope)
beta_aware<-0.55              # logistic function alpha parameter for awareness function (midpoint)
fatigue_shape<-2.34           # weibull distribution shape parameter (rweibull)
fatigue_scale<-43.46          # weibull distribution scale parameter (rweibull)
alpha_hosp<-13                # logistic function alpha parameter for readoption function (slope)
beta_hosp<-0.50               # logistic function beta parameter for readoption function (midpoint)
hosp_window<- 7               # OPTION to only reassess behavior based on % change in hospitalizations based on window of X days (days in assessment window)
hosp_threshold<- 0.05         # OPTION to only reassess behavior based on % change (this is the percent change)
awareness<- T                 # Turn ON or OFF the awareness function (TRUE/FALSE)
behavior<- T                  # Turn ON or OFF the behavior function (TRUE/FALSE)
fatigue<- T                   # Turn ON or OFF the fatigue function (TRUE/FALSE)
readopt<- T                   # Turn ON or OFF readoption (TRUE/FALSE)
gate<- T                      # Turn ON or OFF hospital function for readoption (TRUE/FALSE): readoption probability multiplier
threshold<- F                 # Turn ON or OFF percent change in hospitalizations for behavior reassessment
scaling_factor<- 100          # Normalize hospitalization rate to range recognized by XGBoost function (divided by scaling factor)

# variables of interest (VOI) that the XGBoost function uses to assess behavior 
voi<- c("age", 
        "gender", 
        "hospital_occupancy_per_100k", 
        "perc_severe", "willing_to_isolate", 
        "working_outside_home")


first_infected="random"      # OPTIONS: "random", "degree", "eigenvector", "betweenness", "closeness"
starting_infections=2        # NUMERIC: choose how many starting infections 


# Function to loop over the three synthetic networks 

for(q in seq_along(networks)){
  
  # Assign network type
  network<- networks[[q]]
  
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
  
  
  # create cluster with X cores (the number subtracted is the number of cores saved for other tasks)
  cl <- makeCluster(parallel::detectCores() - 2)
  
  # export everything requried to run the model to each core
  clusterExport(cl, c("network", "model_params", "first_infected", "starting_infections", "sim_centralities", 
                      "xg_behavior_model","run_sihr_network", "run_model_functon"))
  
  # load the packages each core will need to run the model
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
  
  # set cluster seed for reproducibility
  clusterSetRNGStream(cl, iseed = 123)
  
  # parallel function 1:number of simulations desired
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








