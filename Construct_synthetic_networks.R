#### Generate Synthetic Networks ####

setwd("...")

library(igraph)
library(tidyverse)
library(Matrix)

#Import Imperial College/YouGov Netherlands COVID-19 Behavior Tracker Survey Data#

nl_yougov_dataset<- read.csv("nl_yougov_dataset.csv")

outcome<- c("social_distance_binary")

predictors<- c("age", "gender",  "hospital_occupancy_per_100k", "perc_severe", "willing_to_isolate", "working_outside_home")

nl_df<- nl_yougov_dataset %>% 
  filter(date>="2020-06-24" && date<="2021-01-13") %>% 
  dplyr::select(all_of(c(outcome,predictors))) %>%
  na.omit %>% mutate(gender=case_when(gender=="Male"~0, gender=="Female"~1))



################################################################################

# Small-World Network

set.seed(95)  # For reproducibility

# Step 1: Create a Small-World Network (Watts-Strogatz model)
n <- 10000          # number of agents
k <- 5              # each node connected to k nearest neighbors
p <- 0.05           # rewiring probability (low = more clustered)

sw <- sample_smallworld(1, n, k, p)

small_world_summary<- 
  data.frame(nodes=length(V(sw)),
             edges=length(E(sw)),
             mean_degree=mean(degree(sw)),
             min_degree=min(degree(sw)),
             max_degree=max(degree(sw)),
             clustering=transitivity(sw),
             density=edge_density(sw),
             mean_path_length=mean_distance(sw),
             diameter=diameter(sw),
             betweenness=betweenness(sw, normalized = T),
             eigen_centrality=eigen_centrality(sw)$vector,
             closeness=closeness(sw)) %>%
  summarize(nodes=mean(nodes),
            edges=mean(edges),
            mean_degree=mean(mean_degree),
            min_degree=mean(min_degree),
            max_degree=mean(max_degree),
            clustering=mean(clustering),
            density=mean(density),
            mean_path_length=mean(mean_path_length),
            diameter=mean(diameter),
            mean_betweenness=mean(betweenness),
            betweenness_lower=quantile(betweenness, 0.025),
            betweenness_upper=quantile(betweenness, 0.975),
            mean_eigen=mean(eigen_centrality),
            eigen_lower=quantile(eigen_centrality, 0.025),
            eigen_upper=quantile(eigen_centrality, 0.975),
            mean_closeness=mean(closeness),
            closeness_lower=quantile(closeness, 0.025),
            closeness_upper=quantile(closeness, 0.975))


sw_centralities<- data.frame(network=rep("Small world",n),
                             degree=degree(sw),
                             eigenvector=eigen_centrality(sw, directed = F)$vector,
                             betweenness=betweenness(sw, normalized=T, directed = F),
                             closeness=closeness(sw, normalized = T))


# Assign agent characteristics from behavioral data

V(sw)$age <- sample(nl_df$age, n, replace = T)
V(sw)$gender<- rbinom(n,1,mean(nl_df$gender))
V(sw)$working_outside_home <- rbinom(n,1,mean(nl_df$working_outside_home))
V(sw)$perc_severe<- sample(nl_df$perc_severe, n, replace = T) 
V(sw)$willing_to_isolate<- sample(nl_df$willing_to_isolate, n, replace = T)



################################################################################



# Preferential Attachment Network

set.seed(45)

n=10000   # number of nodes
m=5       # minimum number of edges (m*2 = mean degree)

pa<- sample_pa(n=n, m=m, start.graph = make_full_graph(2, directed = F), directed = F)


pref_attach_summary<- 
  data.frame(nodes=length(V(pa)),
             edges=length(E(pa)),
             mean_degree=mean(degree(pa)),
             min_degree=min(degree(pa)),
             max_degree=max(degree(pa)),
             clustering=transitivity(pa),
             density=edge_density(pa),
             mean_path_length=mean_distance(pa),
             diameter=diameter(pa),
             betweenness=betweenness(pa, normalized = T),
             eigen_centrality=eigen_centrality(pa)$vector,
             closeness=closeness(pa)) %>%
  summarize(nodes=mean(nodes),
            edges=mean(edges),
            mean_degree=mean(mean_degree),
            min_degree=min(min_degree),
            max_degree=max(max_degree),
            clustering=mean(clustering),
            density=mean(density),
            mean_path_length=mean(mean_path_length),
            diameter=mean(diameter),
            mean_betweenness=mean(betweenness),
            betweenness_lower=quantile(betweenness, 0.025),
            betweenness_upper=quantile(betweenness, 0.975),
            mean_eigen=mean(eigen_centrality),
            eigen_lower=quantile(eigen_centrality, 0.025),
            eigen_upper=quantile(eigen_centrality, 0.975),
            mean_closeness=mean(closeness),
            closeness_lower=quantile(closeness, 0.025),
            closeness_upper=quantile(closeness, 0.975))


pa_centralities<- data.frame(network=rep("Preferential attachment",n),
                             degree=degree(pa),
                             eigenvector=eigen_centrality(pa, directed = F)$vector,
                             betweenness=betweenness(pa, normalized=T, directed = F),
                             closeness=closeness(pa, normalized = T))



# Assign agent characteristics from behavioral data

V(pa)$age <- sample(nl_df$age, n, replace = T)
V(pa)$gender<- rbinom(n,1,mean(nl_df$gender))
V(pa)$working_outside_home <- rbinom(n,1,mean(nl_df$working_outside_home))
V(pa)$perc_severe<- sample(nl_df$perc_severe, n, replace = T) 
V(pa)$willing_to_isolate<- sample(nl_df$willing_to_isolate, n, replace = T)



################################################################################



# Random Network

set.seed(53)

r<- sample_gnm(10000, 50000, directed=F) #(nodes, edges)


random_graph_summary<- 
  data.frame(nodes=length(V(r)),
             edges=length(E(r)),
             mean_degree=mean(degree(r)),
             min_degree=min(degree(r)),
             max_degree=max(degree(r)),
             clustering=transitivity(r),
             density=edge_density(r),
             mean_path_length=mean_distance(r),
             diameter=diameter(r),
             betweenness=betweenness(r, normalized = T),
             eigen_centrality=eigen_centrality(r)$vector,
             closeness=closeness(r)) %>%
  summarize(nodes=mean(nodes),
            edges=mean(edges),
            mean_degree=mean(mean_degree),
            min_degree=min(min_degree),
            max_degree=max(max_degree),
            clustering=mean(clustering),
            density=mean(density),
            mean_path_length=mean(mean_path_length),
            diameter=mean(diameter),
            mean_betweenness=mean(betweenness),
            betweenness_lower=quantile(betweenness, 0.025),
            betweenness_upper=quantile(betweenness, 0.975),
            mean_eigen=mean(eigen_centrality),
            eigen_lower=quantile(eigen_centrality, 0.025),
            eigen_upper=quantile(eigen_centrality, 0.975),
            mean_closeness=mean(closeness, na.rm=T),
            closeness_lower=quantile(closeness, 0.025, na.rm=T),
            closeness_upper=quantile(closeness, 0.975, na.rm=T))


r_centralities<- data.frame(network=rep("Random",n),
                            degree=degree(r),
                            eigenvector=eigen_centrality(r, directed = F)$vector,
                            betweenness=betweenness(r, normalized=T, directed = F),
                            closeness=closeness(r, normalized = T))


# Assign agent characteristics from behavioral data

V(r)$age <- sample(nl_df$age, n, replace = T)
V(r)$gender<- rbinom(n,1,mean(nl_df$gender))
V(r)$working_outside_home <- rbinom(n,1,mean(nl_df$working_outside_home))
V(r)$perc_severe<- sample(nl_df$perc_severe, n, replace = T) 
V(r)$willing_to_isolate<- sample(nl_df$willing_to_isolate, n, replace = T)



