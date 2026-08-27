#### Generate Synthetic Networks ####

library(igraph)
library(tidyverse)
library(Matrix)

# Import Imperial College/YouGov Netherlands COVID-19 Behavior Tracker Survey Data

nl_df<- readRDS("nl_yougov_data.rds") 

# Sample for the number of nodes, arrange in decreasing order of network size

sample_df<- 
  slice_sample(nl_df, n=10000, replace=T) %>%
  arrange(desc(network_size))


################################################################################

# Small-World Network

set.seed(95)  # For reproducibility

# Step 1: Create a Small-World Network (Watts-Strogatz model)
n <- 10000          # number of agents
k <- 5              # each node connected to k nearest neighbors
p <- 0.05           # rewiring probability (low = more clustered)

sw <- sample_smallworld(1, n, k, p)

# Assign agent characteristics from behavioral data based on degree order, 
# observations with a greater network size are assigned to nodes with the greatest degree

degree_order <- order(degree(sw), decreasing = TRUE)

V(sw)$age[degree_order] <- sample_df$age
V(sw)$gender[degree_order] <- sample_df$gender
V(sw)$working_outside_home[degree_order] <- sample_df$working_outside_home
V(sw)$perc_severe[degree_order] <- sample_df$perc_severe
V(sw)$willing_to_isolate[degree_order] <- sample_df$willing_to_isolate



################################################################################



# Preferential Attachment Network

set.seed(45)

n=10000   # number of nodes
m=5       # minimum number of edges (m*2 = mean degree)

pa<- sample_pa(n=n, m=m, start.graph = make_full_graph(2, directed = F), directed = F)

# Assign agent characteristics from behavioral data

degree_order <- order(degree(pa), decreasing = TRUE)

V(pa)$age[degree_order] <- sample_df$age
V(pa)$gender[degree_order] <- sample_df$gender
V(pa)$working_outside_home[degree_order] <- sample_df$working_outside_home
V(pa)$perc_severe[degree_order] <- sample_df$perc_severe
V(pa)$willing_to_isolate[degree_order] <- sample_df$willing_to_isolate



################################################################################


# Random Network

set.seed(53)

r<- sample_gnm(10000, 50000, directed=F) #(nodes, edges)

# Assign agent characteristics from behavioral data

degree_order <- order(degree(r), decreasing = TRUE)

V(r)$age[degree_order] <- sample_df$age
V(r)$gender[degree_order] <- sample_df$gender
V(r)$working_outside_home[degree_order] <- sample_df$working_outside_home
V(r)$perc_severe[degree_order] <- sample_df$perc_severe
V(r)$willing_to_isolate[degree_order] <- sample_df$willing_to_isolate




