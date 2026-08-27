library(ParBayesianOptimization)
library(doParallel)
library(arm)
library(tidytext)
library(xgboost)
library(matrixStats)
library(tidyverse)
library(ggplot2)
library(DescTools)
library(ResourceSelection)
library(logbin)
library(car)
library(sure)
library(sandwich)
library(lmtest)
library(outliers)
library(Metrics)
library(brant)
library(pscl)
library(VGAM)
library(broom)
library(pROC)
library(pheatmap)
library(explainer)
library(minpack.lm)
library(gghalves)
library(ggforce)
library(ggbeeswarm)
library(ggpubr)
library(gam)
library(mgcv)

nl_yougov_data<- readRDS("nl_yougov_data.rds")

outcome<- c("social_distance_binary")

predictors<- c("age", 
               "gender",  
               "hospital_occupancy_per_100k", 
               "perc_severe", 
               "willing_to_isolate", 
               "working_outside_home")

temp_df<- nl_yougov_data %>% 
  dplyr::select(all_of(c(outcome,predictors))) 



tuning_df<- temp_df

# Detect available cores and start cluster

num_cores <- parallel::detectCores() - 1   # leave 1 core free
cl <- makeCluster(num_cores)
registerDoParallel(cl) 



make_scoring_function <- function(xg_data, xg_labels) {
  
  xg_data<- data.matrix(xg_data)
  
  xg_labels<- data.matrix(xg_labels)
  
  function(eta, max_depth, subsample, colsample_bytree, gamma, lambda, alpha, min_child_weight) {
    
    library(xgboost)
    
    dtrain<- xgb.DMatrix(data = xg_data, label= xg_labels)
    
    # ensure package available on workers
    
    params <- list(
      objective = "binary:logistic",
      eval_metric = "logloss",
      eta = eta,
      max_depth = as.integer(max_depth),
      subsample = subsample,
      colsample_bytree = colsample_bytree,
      gamma = gamma,
      lambda = lambda, 
      alpha = alpha,
      min_child_weight = min_child_weight
    )
    
    cv <- xgb.cv(
      params = params,
      data = dtrain,
      nrounds = 1000,
      nfold = 4,
      stratified = TRUE,
      early_stopping_rounds = 50,
      verbose = 0
    )
    
    best_logloss <- min(cv$evaluation_log$test_logloss_mean)
    list(Score = -best_logloss)
  }
}

# ---- Bayesian Optimization bounds ----
bounds <- list(
  eta = c(0.01, 0.3),
  max_depth = c(3L, 8L),
  subsample = c(0.6, 1.0),
  colsample_bytree = c(0.6, 1.0),
  gamma = c(0, 5),
  lambda = c(0.5, 5),
  alpha= c(0,5),
  min_child_weight = c(1L, 10L) 
)



xgb_df<- tuning_df %>%
  mutate(across(where(is.factor), as.numeric)) %>%                     # factors → numeric codes
  mutate(across(where(is.character), ~ as.numeric(as.factor(.)))) %>%  # characters → factor → numeric codes
  as.matrix()

xg_data<- data.matrix(xgb_df[,-1])

xg_labels<- data.matrix(xgb_df[,1])


# make scoring function for this outcome
scoringFunction <- make_scoring_function(xg_data, xg_labels)


#clusterExport(cl, varlist = c("xg_data", "xg_labels"), envir = environment())

# run Bayesian Optimization
opt <- bayesOpt(
  FUN = scoringFunction,
  bounds = bounds,
  initPoints = 10,
  iters.n = 20,
  acq = "ei",
  parallel = TRUE
)

# store best row
opt_hyperparams <- data.frame(opt$scoreSummary[which.max(opt$scoreSummary$Score), ], stringsAsFactors = FALSE)
opt_output<- data.frame(opt$scoreSummary)


# ---- Stop parallel cluster ----
stopCluster(cl)



### Running new XGBoost

k="social_distance_binary"

set.seed(1675)

n<- nrow(temp_df)
index<- sample(seq_len(n))

training_index<- index[1:floor(0.80*n)]
testing_index<- index[(floor(0.80*n)+1):n]

xgb_parms<- opt_hyperparams %>% dplyr::select(c(eta,max_depth,subsample,colsample_bytree,gamma,lambda,alpha,min_child_weight))

xgb_df<- temp_df

ncol<- ncol(xgb_df)

xg_data<- data.matrix(xgb_df[,-1])

xg_labels<- data.matrix(xgb_df[,1])

xg_training_data<- data.matrix(xg_data[training_index,]) 

xg_training_labels<- data.matrix(xg_labels[training_index,]) 

xg_testing_data<- data.matrix(xg_data[testing_index,]) 

xg_testing_labels<- data.matrix(xg_labels[testing_index,]) 


xgb_function<- function(xg_training_data,
                        xg_training_labels,
                        xg_testing_data,
                        xg_testing_labels,
                        xgb_parms){
  
  
  dtrain<- xgb.DMatrix(data = xg_training_data, label= xg_training_labels)
  
  dtest<- xgb.DMatrix(data = xg_testing_data, label= xg_testing_labels)
  
  params=list(objective="binary:logistic",
              eval_metric="logloss",
              max_depth = xgb_parms$max_depth,         # smaller trees → less overfitting
              eta = xgb_parms$eta,            # slower learning → smoother optimization
              subsample = xgb_parms$subsample,       # random row sampling → better generalization
              colsample_bytree = xgb_parms$colsample_bytree, # random feature sampling → prevents dominance
              lambda = xgb_parms$lambda,            # stronger L2 regularization
              alpha = xgb_parms$alpha,             # add L1 regularization
              gamma = xgb_parms$gamma,
              min_child_weight = xgb_parms$min_child_weight,
              nthread = parallel::detectCores() - 1)
  
  
  cv_output <- 
    xgb.cv(
      params = params,
      data = dtrain,
      nrounds = 1500,
      nfold = 5,
      early_stopping_rounds = 50,
      verbose = TRUE
    )
  
  
  optimal_rounds<- cv_output$best_iteration
  
  
  xg_model <- xgb.train(params=params,
                        data = dtrain, # the data   
                        nrounds = optimal_rounds) # max number of boosting iterations
  
  
  xg_importance <- xgb.importance(model = xg_model) %>% dplyr::select("Feature", "Gain") %>% rename(variable=Feature, importance=Gain)
  
  shap_vals <- predict(xg_model, dtrain, predcontrib = TRUE)
  
  shap_interactions<- predict(xg_model, dtrain, predinteraction=TRUE)
  
  shap_avg_interactions<- apply(shap_interactions, c(2,3), mean)
  
  shap_avg_interactions<- shap_avg_interactions[-nrow(shap_avg_interactions), -ncol(shap_avg_interactions)]
  
  shap_abs_interactions<- apply(abs(shap_interactions), c(2,3), mean)
  
  shap_abs_interactions<- shap_abs_interactions[-nrow(shap_abs_interactions), -ncol(shap_abs_interactions)]
  
  # Remove bias column
  shap_vals_df <- shap_vals[, -ncol(shap_vals)]
  
  shaps_df <- data.frame(
    variable = colnames(shap_vals_df),
    shap_avg = colMeans(shap_vals_df),
    shap_med = colMedians(shap_vals_df),
    shap_lower_25 = colQuantiles((shap_vals_df), probs = 0.25),
    shap_upper_75 = colQuantiles((shap_vals_df), probs = 0.75),
    shap_lower_95 = colQuantiles((shap_vals_df), probs = 0.025),
    shap_upper_95 = colQuantiles((shap_vals_df), probs = 0.975),
    shap_abs_avg = colMeans(abs(shap_vals_df)),
    shap_abs_med = colMedians(abs(shap_vals_df)),
    shap_abs_lower_25 = colQuantiles(abs(shap_vals_df), probs = 0.25),
    shap_abs_upper_75 = colQuantiles(abs(shap_vals_df), probs = 0.75),
    shap_abs_lower_95 = colQuantiles(abs(shap_vals_df), probs = 0.025),
    shap_abs_upper_95 = colQuantiles(abs(shap_vals_df), probs = 0.975)
  ) 
  #%>% mutate(bias=mean(shap_vals[,ncol(shap_vals)]))
  
  rownames(shaps_df) <- NULL
  
  shap_vals_df <- as.data.frame(shap_vals_df)
  
  shap_vals_contr<-
    as.data.frame(shap_vals[, -ncol(shap_vals)]) %>% 
    mutate(id=row_number()) %>%
    pivot_longer(-c(id), names_to="feature", values_to="SHAP") %>% 
    mutate(contribution=case_when(SHAP > 0 ~ "Positive",
                                  SHAP < 0 ~ "Negative"))
  
  shap_contribution_df <- 
    shap_vals_contr %>% 
    group_by(contribution,feature) %>%
    summarise(shap_abs_avg=mean(abs(SHAP)),
              shap_abs_lower_95=quantile(abs(SHAP), 0.025),
              shap_abs_upper_95=quantile(abs(SHAP), 0.975),
              shap_avg=mean(SHAP),
              shap_avg_lower_95=quantile(SHAP, 0.025),
              shap_avg_upper_95=quantile(SHAP, 0.975),
              shap_med=median(SHAP),
              shap_lower_25=quantile(SHAP, 0.25),
              shap_upper_75=quantile(SHAP, 0.75),
              .groups = "drop")
  
  shap_vals_df$label <- xg_training_labels[,1] 
  
  shap_vals_df_long<-
    shap_vals_df %>% 
    mutate(id=row_number()) %>%
    pivot_longer(-c(id, label), names_to="feature", values_to="SHAP")
  
  feature_vals_long<- 
    as.data.frame(xg_training_data) %>%
    mutate(id=row_number()) %>% 
    pivot_longer(-id, names_to="feature", values_to="value")
  
  shap_vals_df_long<- shap_vals_df_long %>%
    left_join(feature_vals_long, by=c("id", "feature"))
  
  shap_df_long <- 
    shap_vals_df %>% 
    pivot_longer(-label, names_to="feature", values_to="SHAP") %>%
    group_by(label,feature) %>%
    summarise(shap_abs_avg=mean(abs(SHAP)),
              shap_abs_lower_95=quantile(abs(SHAP), 0.025),
              shap_abs_upper_95=quantile(abs(SHAP), 0.975),
              shap_avg=mean(SHAP),
              shap_avg_lower_95=quantile(SHAP, 0.025),
              shap_avg_upper_95=quantile(SHAP, 0.975),
              shap_med=median(SHAP),
              shap_lower_25=quantile(SHAP, 0.25),
              shap_upper_75=quantile(SHAP, 0.75),
              .groups = "drop")
  
  xg_output<- left_join(shaps_df, xg_importance, by="variable")
  
  
  prediction_values <- predict(xg_model, newdata = dtest)
  prediction_classes <- ifelse(prediction_values > 0.5, 1, 0)
  
  auc_value<- Metrics::auc(xg_testing_labels, prediction_values)
  logloss_value <- Metrics::logLoss(xg_testing_labels, prediction_values)
  
  prediction_df<- as.data.frame(cbind(prediction_values, prediction_classes, actual=xg_testing_labels)) %>% 
    rename(probability=prediction_values, prediction=prediction_classes, actual=V3) %>% 
    rowwise %>% 
    mutate(success=case_when(prediction==1 && actual==1~1,
                             prediction==0 && actual==0~1,
                             TRUE~0),
           success_one=case_when(prediction==1 && actual==1~1,
                                 TRUE~0),
           success_zero=case_when(prediction==0 && actual==0~1,
                                  TRUE~0))
  
  prediction_df_xg<- prediction_df
  
  colnames(prediction_df_xg) <- paste0(colnames(prediction_df_xg), "_xg")
  
  xg_output<-
    cbind(
      model="xgb",
      xg_output,
      auc=rep(auc_value, nrow(xg_output)),
      logloss=rep(logloss_value, nrow(xg_output)),
      predictive_value=sum(prediction_df$success)/nrow(prediction_df),
      predictive_value_ones=sum(prediction_df$success_one)/sum(prediction_df$actual),
      predictive_value_zeros=sum(prediction_df$success_zero)/(nrow(prediction_df) - sum(prediction_df$actual)))
  
  
  return(list(xg_output, prediction_df_xg, shap_vals_df, shap_avg_interactions, shap_abs_interactions, shap_df_long, shap_vals_df_long, shap_contribution_df, xg_model))
  
}


xgb_list<-xgb_function(xg_training_data,
                       xg_training_labels,
                       xg_testing_data,
                       xg_testing_labels,
                       xgb_parms)


xgb_output<-xgb_list[[1]]

xgb_predictions<-xgb_list[[2]]

xgb_shaps<-as.data.frame(xgb_list[[3]])

xgb_shap_avg_int<- xgb_list[[4]]

xgb_shap_abs_int<- xgb_list[[5]]

shap_long<- xgb_list[[6]]

full_shap<- xgb_list[[7]]

shap_contributions <- xgb_list[[8]]


xg_behavior_model<- xgb_list[[9]]

saveRDS(xg_behavior_model, "xg_behavior_model.rds")

