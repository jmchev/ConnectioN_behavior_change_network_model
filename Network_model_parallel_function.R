#### Behavior Network Model Parameters ####

run_model_functon<- function(k,network,first_infected,starting_infections,sim_centralities, model_params){
  
  t0 <- Sys.time()
  
  g<-network
  
  if(first_infected=="random"){
    
    samples<- sim_centralities$nodes
    
  }else if(first_infected=="degree"){
    
    samples<- order(sim_centralities$degree, decreasing = TRUE)[1:starting_infections]
    
  }else if(first_infected=="eigenvector"){
    
    samples<- order(sim_centralities$eigenvector, decreasing = TRUE)[1:starting_infections]
    
  }else if(first_infected=="betweenness"){
    
    samples<- order(sim_centralities$betweenness, decreasing = TRUE)[1:starting_infections]
    
  }else if(first_infected=="closeness"){
    
    samples<- order(sim_centralities$closeness, decreasing = TRUE)[1:starting_infections]
    
  }
  
  initial_infected <- as.numeric(sample(samples, starting_infections))
  V(g)$state[initial_infected] <- "I"
  V(g)$time_infected[initial_infected] <- 0
  
  sihr_initial<- data.table(day=0,
                            S=sum(V(g)$state=="S"),
                            I=sum(V(g)$state=="I"),
                            H=sum(V(g)$state=="H"),
                            R=sum(V(g)$state=="R"),
                            A=sum(V(g)$aware),
                            B=sum(V(g)$behavior),
                            percent_masked=0,
                            HR=0,
                            Rt=NA)
  
  
  network_results<- 
    run_sihr_network(g, model_params)
  
  sihr_df<- rbindlist(list(sihr_initial, network_results[[1]]))
  
  sihr_df[ , `:=` (
    int_infected=first_infected,
    sim=k)]
  
  node_summary<- network_results[[2]] #%>% mutate(starting_infection=case_when(time_infected==0~1,TRUE~0))
  
  peak_prev<- network_results[[3]]
  
  prev_day<- network_results[[4]]
  
  prev_network<- network_results[[5]]
  
  peak_behavior<- network_results[[6]]
  
  behavior_day<- network_results[[7]]
  
  behavior_network<- network_results[[8]]
  
  node_summary[ , `:=` (
    starting_infection=case_when(time_infected==0~1,
                                 TRUE~0),
    degree=sim_centralities$degree,
    closeness=sim_centralities$closeness,
    betweenness=sim_centralities$betweenness,
    eigenvector=sim_centralities$eigenvector,
    peak_prev= peak_prev,
    peak_prev_day= prev_day,
    prev_degree= degree(prev_network),
    prev_eigen= eigen_centrality(prev_network)$vector,
    prev_betw= betweenness(prev_network, normalized = T),
    prev_close=closeness(prev_network, normalized = T),
    disconnected_nodes_pn=sum(degree(prev_network) == 0),
    peak_behavior= peak_behavior,
    peak_behavior_day= behavior_day,
    behavior_degree= degree(behavior_network),
    behavior_eigen= eigen_centrality(behavior_network)$vector,
    behavior_betw= betweenness(behavior_network, normalized = T),
    behavior_close=closeness(behavior_network, normalized = T),
    disconnected_nodes_bn=sum(degree(behavior_network) == 0),
    sim=k
  )]
  
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("k = %d finished in %.1f sec\n", k, elapsed), 
      file = "sim_progress.log", append = TRUE)
  
  
  return(list(sihr_df, node_summary))
  
}





















