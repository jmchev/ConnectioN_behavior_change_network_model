library(igraph)
library(RColorBrewer)
library(magick)
library(tidyverse)
library(truncnorm)
library(data.table)
library(readr)
library(jsonlite)
library(Matrix)
library(xgboost)
library(finalsize)
library(corrplot)
library(naniar)


#### Network Model Function ####

run_sihr_network<-
  function(g, model_params){
    
    # assign model parameters from list (ensure the order aligns with that specified in the run file)
    n<- model_params[[1]]
    timesteps<- model_params[[2]]
    infection_prob<- model_params[[3]]
    hosp_prob<- model_params[[4]]
    recovery_time_I<- model_params[[5]]
    recovery_time_H<- model_params[[6]]
    mu<- model_params[[7]]
    alpha_aware<- model_params[[8]]
    beta_aware<- model_params[[9]]
    fatigue_shape<- model_params[[10]]
    fatigue_scale<- model_params[[11]]
    alpha_hosp<- model_params[[12]]
    beta_hosp<- model_params[[13]]
    hosp_window<- model_params[[14]]
    hosp_threshold<- model_params[[15]]
    awareness<- model_params[[16]]
    behavior<- model_params[[17]] 
    fatigue<- model_params[[18]] 
    readopt<- model_params[[19]]
    gate<- model_params[[20]]
    threshold<- model_params[[21]]
    voi<- model_params[[22]]
    scaling_factor<- model_params[[23]]
  
    N <- vcount(g)
    
    sihr_df<- data.table(day=1:timesteps,
                         S=numeric(timesteps),
                         I=numeric(timesteps),
                         H=numeric(timesteps),
                         R=numeric(timesteps),
                         A=numeric(timesteps),
                         B=numeric(timesteps),
                         percent_masked=numeric(timesteps),
                         HR=numeric(timesteps))

    
    # full adjacency matrix of network
    A <- as_adjacency_matrix(g, sparse = TRUE) 
    
    # de-duplicated edge list of full network
    edges <- which(A != 0, arr.ind = TRUE)
    edges <- edges[edges[,1] < edges[,2], , drop = FALSE]
    
    # initialize the active edge vector, they all begin as TRUE
    edge_active<- rep(TRUE, nrow(edges))
    
    # Social distancing mu parameter OPTIONS (if mu>1 that is the maximum number of contacts kept)
    if(mu<1){
      
      mu_vec <- rep(mu, vcount(g))
      
    }else if(mu>=1){
      
      mu_vec <- ifelse(degree(g) <= mu, 1, mu / pmax(1, degree(g)))
      
    }
    
    adopted <- integer(0)
    fatigued <- integer(0)
    
    # record active edges at behavioral and prevalence peaks
    
    temp_network <- graph_from_adjacency_matrix(A, mode = "undirected")
    
    peak_prev <- 0
    peak_prev_A <- A
    peak_prev_day <- NA_integer_
    
    peak_behavior <- 0
    peak_behavior_A <- A
    peak_behavior_day <- NA_integer_
    
    
    # A_reduced is used in our infection step, initialize it here because it only (re)builds during the loop if there is behavior change
    A_reduced<- A
    
    # list of degrees of all agents
    deg<- degree(g)
    
    # we initialize our xgboost input data from the network agents and only update hospitalizations during the loop
    pred_df <- data.frame(
      age = as.numeric(V(g)$age),
      gender = as.numeric(V(g)$gender),
      hospital_occupancy_per_100k = NA,
      perc_severe = as.numeric(V(g)$perc_severe),
      willing_to_isolate = as.numeric(V(g)$willing_to_isolate),
      working_outside_home = as.numeric(V(g)$working_outside_home)
    )
    
    adoption_times <- vector("list", vcount(g))
    abandon_times <- vector("list", vcount(g))
    hr_at_adoption <- vector("list", vcount(g))
    
    # track the effective reproduction number
    rt_tracker <- data.table(
      t = 1:timesteps,
      new_infected = NA_integer_,
      current_infectious = NA_integer_
    )
    
    
    # per day state transition loop
    for (t in 1:timesteps) {   
      
      print(paste("Starting timestep:", t))
      
      infected <- which(V(g)$state == "I")
      
      current_hosp <- sum(V(g)$state=="H")
      
      # running max hospitalizations
      if (t == 1) {
        max_hosp <- current_hosp
      } else {
        max_hosp <- max(max_hosp, current_hosp)
      }
      
      # hospital ratio (CURRENT:RUNNING MAX)
      hosp_ratio<- ifelse(max_hosp>0, current_hosp/max_hosp, 0)
      
      # awareness state transitions if TRUE
      if(awareness==TRUE) {
        
        if(length(infected) > 0) {
          
          V(g)$aware[infected] <- 1
          V(g)$time_aware[infected][is.na(V(g)$time_aware[infected])] <- t
          
        }
        
        aware<- which(V(g)$aware == 1)
        
        naive<- which(V(g)$aware == 0)
        
        if (length(naive) > 0) {
          
          aware_counts <- as.numeric(A %*% V(g)$aware)
          
          prop_aware <- aware_counts[naive] / pmax(1, deg[naive])
          
          aware_probs <- ifelse(prop_aware>0, plogis(alpha_aware*(prop_aware-beta_aware)), 0)
          
          awoke <- naive[rbinom(length(naive), 1, aware_probs)==1]
          
          V(g)$aware[awoke] <- 1
          V(g)$time_aware[awoke] <- t
          
        }
        
      }
      
      print("awareness done")
      
      # behavior state transitions if TRUE
      if(behavior==TRUE){
        
        #Update times of behavior and behavior abandonment and implement behavioral fatigue
        
        V(g)$days_behavior<- V(g)$days_behavior + V(g)$behavior
        
        V(g)$total_days_behavior <- V(g)$total_days_behavior + V(g)$behavior
        
        abandoned <- which(
          V(g)$behavior == 0 &
            V(g)$times_abandoned>=1
        )
        
        if(length(abandoned) >0){
          
          V(g)$days_abandoned[abandoned] <-
            V(g)$days_abandoned[abandoned] + 1
          
          V(g)$total_days_abandoned[abandoned] <-
            ifelse(is.na(V(g)$total_days_abandoned[abandoned]), 0, V(g)$total_days_abandoned[abandoned] + 1)
          
        }
        
        fatigued <- which(
          
          V(g)$behavior == 1 &
            V(g)$days_behavior >= V(g)$fatigue_time
          
        )
        
        # update fatigued agents
        
        if(length(fatigued) >0){
          
          V(g)$behavior[fatigued] <- 0
          
          V(g)$days_behavior[fatigued]<- 0
          
          V(g)$days_abandoned[fatigued]<- 0
          
          V(g)$times_abandoned[fatigued] <- 
            ifelse(is.na(V(g)$times_abandoned[fatigued]), 1, V(g)$times_abandoned[fatigued] + 1)
          
          abandon_times[fatigued] <- lapply(
            abandon_times[fatigued], function(x) c(x, t)
          )
          
        }
        
        print("fatigued done")
        
        # OPTION: calculate hospitalization percent change metric, can be used to gate behavior change check
        
        if (t <= (hosp_window*2)){
          
          hosp_diff <- sum(V(g)$state == "H")
          
        }else{
          
          avg_recent <- mean(sihr_df$H[(t-hosp_window):(t-1)])
          avg_prior  <- mean(sihr_df$H[(t-(hosp_window*2)):(t-(hosp_window+1))])
          hosp_diff  <- ifelse(avg_prior==0, 0, (avg_recent - avg_prior)/avg_prior)
          
        } 
        
        print("hosp_diff calculated")
        
        if(threshold==T && hosp_diff >= hosp_threshold){
          
          door<- "open"
          
        }else if(threshold==T && hosp_diff < hosp_threshold){
          
          door<- "closed"
          
        }else if(threshold==F){
          
          door<- "open"
          
        }
        
        print(paste("door", door))
        
        # If door is open, behavior adoption is assessed
          
        if(door=="open"){
          
          # who is eligible to adopt behavior, readoption is TRUE or FALSE
          
          if(readopt==TRUE){
            
            behavior_eligible<- which(V(g)$aware==1 & V(g)$behavior==0)
            
          }else{
            
            behavior_eligible<- which(V(g)$aware==1 & V(g)$behavior==0 & is.na(V(g)$times_abandoned))
            
          }
          
          # hospitalization gate dependent on hospitalization ratio 
          
          if(length(behavior_eligible) > 0){
            
            if(gate==TRUE){
              
              # calculate probability multiplier from logistic function
              
              hosp_gate <- ifelse(hosp_ratio==0, 0, ifelse(hosp_ratio<1, plogis(alpha_hosp*(hosp_ratio-beta_hosp)), 1))
                
            }else{
              
              hosp_gate <- 1
              
            }
            
            print("gate was opened")
            
            # update hospitalizations in prediction data frame based on H at time t, normalize with scaling factor
            
            pred_df$hospital_occupancy_per_100k = sum(V(g)$state=="H")/N*1e5/scaling_factor
            
            # predict agent behavior change using XGBoost for eligible nodes
            
            dpred <- xgb.DMatrix(as.matrix(pred_df[behavior_eligible,]))
            contributions <- predict(xg_behavior_model, dpred, predcontrib = TRUE)
            
            # Sum only the features that we want to drive probability (VOI)
            # contributions has one column per feature plus a BIAS column
            
            # assigned in initial parameters
            selected_features <- voi 
            
            # sum the marginal probabilities
            margin <- rowSums(contributions[, selected_features, drop = FALSE]) +
              contributions[, "BIAS"]
            
            #probability of adopting behavior over 7-day period, converted to per day probability
            
            p_behavior <- (1-(1-plogis(margin))^(1/7)) * hosp_gate
            
            print("p_behavior was calculated")
            
            #vector of adopting nodes
            
            adopted <- behavior_eligible[
              rbinom(length(behavior_eligible), 1, p_behavior) == 1]
            
            print(paste("number of agents adopting:", length(adopted)))
            
            #Update nodes that adopted behavior
            
            if (length(adopted) > 0) {
              
              V(g)$behavior[adopted] <- 1
              
              V(g)$total_days_behavior[adopted] <- ifelse(is.na(V(g)$total_days_behavior[adopted]), 0, V(g)$total_days_behavior[adopted])
              
              V(g)$ever_behavior[adopted] <- 1
              
              # draw fatigue time if fatigue is TRUE, otherwise fatigue time = total time steps
              
              if(fatigue==TRUE){
                
                V(g)$fatigue_time[adopted]<- ceiling(rweibull(length(adopted), fatigue_shape, fatigue_scale))
                
              }else{
                
                V(g)$fatigue_time[adopted]<- timesteps
                
              }
              
              first_adoption <- adopted[is.na(V(g)$times_abandoned[adopted])]
              
              V(g)$hospitalizations_at_behavior[first_adoption] <- sum(V(g)$state == "H")
              
              adoption_times[adopted] <- lapply(
                adoption_times[adopted], function(x) c(x, t)
              )
              
              hr_at_adoption[adopted] <- lapply(
                hr_at_adoption[adopted], function(x) c(x, hosp_ratio)
              )
              
            }
            #End of adopted>0
            
            print("end of adoption")
            
          }
          #End of aware>0
          
        }
        #End of hosp_diff>0
         
      }
      #end of behavior=T
      
      # new hospitalizations
      
      newly_hospitalized <- infected[rbinom(length(infected), 1, hosp_prob) == 1]
      V(g)$state[newly_hospitalized] <- "H"
      
      
      # 1. Create a active edge matrix for edge retention based on behavioral state
      
      # Vector indicating which nodes are currently practicing behavior
      behavior_vector <- as.numeric(V(g)$behavior == 1)
      
      # A vector of which nodes have changed their behavior by either adopting or abandoning
      changed_nodes <- c(adopted, fatigued)
      
      print(paste("number of changed nodes:", length(changed_nodes)))
      
      # We only update our sparse matrix if there has been behavior change this time step, otherwise it uses the last built sparse matrix
      if(length(changed_nodes) > 0) {
        
        # list of edges to recompute keep probability (only currently affected edges)
        affected_edges <- 
          which(edges[,1] %in% changed_nodes | edges[,2] %in% changed_nodes)
        
        # probability mu of keeping an edge if practicing behavior (all changed edges are redrawn)
        p_keep <- ifelse(
          behavior_vector[edges[affected_edges, 1]] == 1 | 
            behavior_vector[edges[affected_edges, 2]] == 1,
          pmin(mu_vec[edges[affected_edges, 1]], mu_vec[edges[affected_edges, 2]]),
          1)
        
        # update the active edge list with only the newly affected edges, updates for both adopted and abandoned 
        edge_active[affected_edges] <- 
          rbinom(length(affected_edges), 1, p_keep) == 1
        
        # list of all kept and active edges
        edges_kept <- edges[edge_active, , drop = FALSE]
        
        # rebuild the sparse matrix for the infection layer
        A_reduced <- sparseMatrix(
          i = c(edges_kept[,1], edges_kept[,2]),
          j = c(edges_kept[,2], edges_kept[,1]),
          x = 1,
          dims = dim(A)
        )
        
      }
      
      print("end of changed nodes")
      
      current_prev<- sum(V(g)$state=="I")/N
      
      if (current_prev > peak_prev) {
        peak_prev <- current_prev
        peak_prev_A <- A_reduced
        peak_prev_day <- t
      }
      
      current_behavior <- sum(V(g)$behavior == 1)
      
      if (current_behavior > peak_behavior) {
        peak_behavior <- current_behavior
        peak_behavior_A <- A_reduced
        peak_behavior_day <- t
      }
      
      # 2. Vector of infectious nodes
      infectious <- as.numeric(V(g)$state == "I")
      
      # 3. Identify susceptible nodes
      susceptible <- which(V(g)$state == "S")
      
      # 4. Compute number of infectious neighbors of those who are still susceptible using reduced adjacency matrix 
      infectious_counts <- as.numeric(A_reduced[susceptible, ] %*% infectious)
      
      # 5. Compute infection probability per susceptible
      infection_probs <- 1 - (1 - infection_prob)^infectious_counts
      
      new_infections <- susceptible[rbinom(length(susceptible), 1, infection_probs) == 1]
      
      if(length(new_infections)>0){
        
        V(g)$state[new_infections] <- "I"
        V(g)$days_infected[new_infections] <- 0
        V(g)$time_infected[new_infections] <- t
        V(g)$behavior_at_infection[new_infections] <- V(g)$behavior[new_infections]
        
      }
      
      if(length(infected) > 0){
        
        V(g)$days_infected[infected] <- V(g)$days_infected[infected] + 1
        
        recoveries_I <- infected[V(g)$days_infected[infected] >= recovery_time_I]
        V(g)$state[recoveries_I] <- "R"
      }
      
      print("new infections assigned")
      
      rt_tracker[t, `:=`(
        new_infected= length(new_infections),
        current_infectious= sum(infectious))]
        
    
      hospitalized<- which(V(g)$state == "H")
      
      if(length(hospitalized) > 0){
        
        V(g)$days_hospitalized[hospitalized] <- V(g)$days_hospitalized[hospitalized] + 1
        
        recoveries_H <- hospitalized[V(g)$days_hospitalized[hospitalized] >= recovery_time_H]
        V(g)$state[recoveries_H] <- "R"
        
      }
      
      sihr_df[t, `:=`(
        S = sum(V(g)$state=="S"),
        I = sum(V(g)$state=="I"),
        H = sum(V(g)$state=="H"),
        R = sum(V(g)$state=="R"),
        A = sum(V(g)$aware),
        B = sum(V(g)$behavior),
        percent_masked = 1-sum(edge_active)/nrow(edges),
        HR = hosp_ratio
      )]
      
      
      if (sum(V(g)$state=="I") == 0 &&
          sum(V(g)$state=="H") == 0 &&
          sum(V(g)$behavior) == 0) break
      
      print("end of timestep")
      
    }
     #end of timestep loop
    
    #fill in any remaining rows
    if (t < timesteps) {
      sihr_df[(t + 1):timesteps, `:=`(
        S = sihr_df$S[t],
        I = 0,
        H = 0,
        R = sihr_df$R[t],
        A = sihr_df$A[t],
        B = 0,
        percent_masked = sihr_df$percent_masked[t],
        HR = 0
      )]
      
      rt_tracker[(t + 1):timesteps, Rt := NA]
    }
    
    rt_tracker[, Rt := frollsum(new_infected, recovery_time_I) / frollmean(current_infectious, recovery_time_I)]
    
    sihr_df[, Rt := rt_tracker[, Rt]]
    
    peak_prev_network <- graph_from_adjacency_matrix(peak_prev_A, mode = "undirected")
    peak_behavior_network <- graph_from_adjacency_matrix(peak_behavior_A, mode = "undirected")
    
    node_summary <- data.table(
      node = 1:N,
      age = V(g)$age,
      gender = V(g)$gender,
      perc_severe = V(g)$perc_severe,
      willing_to_isolate = V(g)$willing_to_isolate,
      working_outside_home = V(g)$working_outside_home,
      final_state = V(g)$state,
      final_behavior=V(g)$behavior,
      time_infected = V(g)$time_infected,
      closeness_at_infection=V(g)$closeness_at_infection,
      degree_at_infection=V(g)$degree_at_infection,
      days_infected = V(g)$days_infected,
      behavior_at_infection= V(g)$behavior_at_infection,
      hospitalizations_at_behavior = V(g)$hospitalizations_at_behavior,
      days_hospitalized = V(g)$days_hospitalized,
      time_aware = V(g)$time_aware,
      ever_behavior = V(g)$ever_behavior,
      total_days_behavior = V(g)$total_days_behavior,
      total_days_abandoned = V(g)$total_days_abandoned,
      n_adoptions = sapply(adoption_times, length),
      n_abandons = sapply(abandon_times, length),
      first_adoption = sapply(adoption_times, function(x) if(is.null(x)) NA_integer_ else x[1]),
      first_abandon = sapply(abandon_times, function(x) if(is.null(x)) NA_integer_ else x[1]),
      last_adoption = sapply(adoption_times, function(x) if(is.null(x)) NA_integer_ else tail(x, 1)),
      last_abandon = sapply(abandon_times, function(x) if(is.null(x)) NA_integer_ else tail(x, 1)),
      mean_behavior_duration = round(mapply(function(a, b) {
        if(is.null(a) || is.null(b)) return(NA_real_)
        n <- length(b)  # number of completed episodes = number of abandon events
        if(n == 0) return(NA_real_)
        mean(b[1:n] - a[1:n])
      }, adoption_times, abandon_times)),
      max_behavior_duration = mapply(function(a, b) {
        if(is.null(a) || is.null(b)) return(NA_real_)
        n <- length(b)  # number of completed episodes = number of abandon events
        if(n == 0) return(NA_real_)
        max(b[1:n] - a[1:n])
      }, adoption_times, abandon_times),
      min_behavior_duration = mapply(function(a, b) {
        if(is.null(a) || is.null(b)) return(NA_real_)
        n <- length(b)  # number of completed episodes = number of abandon events
        if(n == 0) return(NA_real_)
        min(b[1:n] - a[1:n])
      }, adoption_times, abandon_times),
      mean_abandon_duration = round(mapply(function(a, b) {
        if(is.null(a) || is.null(b) || length(b) < 1 || length(a) < 2) return(NA_real_)
        n <- min(length(b), length(a) - 1)
        mean(a[2:(n+1)] - b[1:n])
      }, adoption_times, abandon_times)),
      max_abandon_duration = mapply(function(a, b) {
        if(is.null(a) || is.null(b) || length(b) < 1 || length(a) < 2) return(NA_real_)
        n <- min(length(b), length(a) - 1)
        max(a[2:(n+1)] - b[1:n])
      }, adoption_times, abandon_times),
      day_max_abandon = mapply(function(a, b) {
        if(is.null(a) || is.null(b)) return(NA_real_)
        n <- min(length(b), length(a) - 1)
        if(n == 0) return(NA_real_)
        gaps <- a[2:(n+1)] - b[1:n]
        a[which.max(gaps) + 1]
      }, adoption_times, abandon_times),
      hr_max_abandon = mapply(function(a, b, hr) {
        if(is.null(a) || is.null(b) || is.null(hr)) return(NA_real_)
        n <- min(length(b), length(a) - 1)
        if(n == 0) return(NA_real_)
        gaps <- a[2:(n+1)] - b[1:n]
        hr[which.max(gaps) + 1]
      }, adoption_times, abandon_times, hr_at_adoption),
      min_abandon_duration = mapply(function(a, b) {
        if(is.null(a) || is.null(b) || length(b) < 1 || length(a) < 2) return(NA_real_)
        n <- min(length(b), length(a) - 1)
        min(a[2:(n+1)] - b[1:n])
      }, adoption_times, abandon_times),
      day_min_abandon = mapply(function(a, b) {
        if(is.null(a) || is.null(b)) return(NA_real_)
        n <- min(length(b), length(a) - 1)
        if(n == 0) return(NA_real_)
        gaps <- a[2:(n+1)] - b[1:n]
        a[which.min(gaps) + 1]  
      }, adoption_times, abandon_times),
      hr_min_abandon = mapply(function(a, b, hr) {
        if(is.null(a) || is.null(b) || is.null(hr)) return(NA_real_)
        n <- min(length(b), length(a) - 1)
        if(n == 0) return(NA_real_)
        gaps <- a[2:(n+1)] - b[1:n]
        hr[which.min(gaps) + 1]  
      }, adoption_times, abandon_times, hr_at_adoption)
    )
    
    return(list(sihr_df, 
                node_summary, 
                peak_prev, 
                peak_prev_day, 
                peak_prev_network, 
                peak_behavior, 
                peak_behavior_day, 
                peak_behavior_network))
    
  }
