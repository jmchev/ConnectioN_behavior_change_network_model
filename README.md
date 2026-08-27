# ConnectioN Project: Agent-based model with machine learning driven behavioral change

This agent-based model was developed in R (4.4.2) for the purpose of pandemic preparedness and response under funding from ZonMw (Netherlands Organization for Health Research and Development; Project number: 10710062310022) at University Medical Center Utrecht. 

The agent-based model utilizes the XGBoost (eXtreme Gradient Boosting) algorithm (R library: xgboost) to predict agent health behavior at each time-step (day) based on assigned agent characteristics (age, gender, perceived COVID-19 severity, willingness to isolate (if directed by health authority), working outside the home (non-remote), and the modelled number of COVID-19 hospitalizations at time t).

The XGBoost model was trained on survey data obtained for the Netherlands available from the Imperial College London & YouGov COVID-19 Behavior Tracker Hub (https://github.com/YouGov-Data/covid-19-tracker). XGBoost hyperparameter tuning and algorithm training are conducted in "Train_xgb_network_model.R" using "nl_yougov_data.rds". The analysis period was 24 June 2020 – 13 January 2021. The full, unfiltered data can be found in the CSV file "nl_yougov_data.csv". For further details on data and analysis please see [4].

The network model utilizes underlying synthetic network structures (small world, random, preferential attachment) to represent the daily contacts among modelled agents (N=10,000) in "Construct_synthetic_networks.R". Agents are assigned characteristics from "nl_yougov_data.rds". 

"SIHR_Network_Function.R" contains the model code. The model cycles over the number of time steps specified (days). Epidemiologically, agents exist in susceptible, infectious, hospitalized, and recovered states. Recovered agents remain immune for the duration of the model and hospitalized agents do not contribute to infections. Behaviorally, agents can be unaware of the epidemic, aware of the epidemic but not practicing behavior, aware of the epidemic and practicing behavior, aware of the epidemic and fatigued from behavior, aware of the epidemic and practicing behavior following re-adoption. Behavioral agents cease physical contact, and therefore infection potential, with 47% of their network members for the duration of behavior.

The model is set-up to run simulations in parallel. All necessary functions, parameters, and dependencies are initialized in "Run_behavior_network_model.R" and passed to "Network_model_parallel_function.R". 

Please see below for further detail on methodology. 

ConnectioN consortium collaborators include: Joshua M Chevalier (model author), Leonard Stellbrink, Florian van Daalen, Lisanne Steijvers, Senne Wijnen, Lilian Kojan, Nannan Li, Beate Jahn, Uwe Siebert, André Calero Valdez, Mickaël Hiligsmann, Rik Crutzen, Nicole Dukers-Muijrers, and Mirjam Kretzschmar (consortium lead). 


## Methods:

### SIHR Transmission Model

Agents in the network are run through an epidemic simulation, where they progress through susceptible, infectious, hospitalized, and recovered disease states. The transmission probability (0.033%) is derived from the reproduction number of SARS-CoV-2 (R0) from 2020, 3.28, assuming a daily contact rate of 10 individuals and a 10-day duration of infectivity. The hospitalization probability was estimated through Bayesian computation using RStan, with an SIHR compartmental model, assuming a duration of hospitalization of 15 days, and fit to Netherlands COVID-19 hospital admissions data from 2020 [1,2].  

Additional agent states include being aware or unaware of the ongoing epidemic and practicing behavior or not practicing behavior. Two randomly infected nodes begin the epidemic for each simulation. Hospitalized agents are assumed to remain isolated for the duration of infection and do not contribute to infections, while recovered agents are immune to reinfection.

### Contact Restricting Behavior

Agents in the behavioral state (aware + behavior) actively practice contact restricting. We derived contact restricting behavior from publicly available secondary data—the Imperial College London YouGov COVID-19 Behavior Tracker Survey Netherlands dataset [3]. The survey asked participants four questions related to social distancing during the analysis period (June 2020–Jan 2021): frequency of avoiding small, medium, and large social gatherings, or crowds. Questions were answered on a five-point Likert scale and were compiled into a composite social distancing score with range 4–20. The score was converted to binary with >16 (average response of 4: “frequently” to each question) representing an individual practicing social distancing. In the survey those with a score >16 reported 47% less contacts from outside the home over the past 7 days, on average, compared to those with a score less than 16. Therefore, the binary variable is associated with an observed reduction in contacts. 

The model assumes all or nothing behavioral participation (contact restricting vs. no contact restricting) and is associated with a 47% reduction in network connections (47% of edges among practicing nodes are temporarily inactivated). Dissolution of edges is a random stochastic process that occurs at the time of behavior adoption where each edge has a 47% chance of being dissolved when either node adopts behavior. Dissolution is not completely symmetric—if a node adopts behavior, but adjoining nodes have already inactivated their edges with that node, all remaining edges still have a 47% probability of being dissolved. However, if an edge between two behavioral nodes is inactive, the edge may reactivate when either node abandons the behavior because the probability is redrawn. Edges are only inactivated on the infection level, assuming reduced physical contact, but not reduced information contact.

### Machine Learning Predicted Behavioral Adoption

Contact restricting adoption probabilities were predicted using a machine learning algorithm (XGBoost) that was trained on the Imperial College London YouGov COVID-19 Behavior Tracker Survey Netherlands dataset and COVID-19 hospitalization data from the Netherlands (The National Institute of Public Health and the Environment; RIVM) from the period June 2020 to January 2021 prior to widespread vaccination. The top predictors of social distancing behavior, as identified in a prior analysis, were COVID-19 hospitalizations, perceived severity of COVID-19, and willingness to isolate [4]. While the original analysis included 24 predictor variables, for the purpose of the agent-based network model, the algorithm was trained only on age, gender, working outside the home, perceived severity, COVID-19 hospitalizations per 100,000, and willingness to isolate. Perceived severity and willingness to isolate were reported on 7-point and 5-point Likert scales, respectively. Agents in the networks were assigned these attributes from selected survey respondents. Agents were arranged in decreasing order of degree and survey observations were arranged by decreasing network size—which was estimated as the sum of the respondents reported household size and average daily number of contacts from outside the home. Assigning attributes in this manner maintains any correlations between the predictor variables, or the predictor variables and social distancing behavior. Using agent-assigned characteristics and the population level hospitalizations at time t, the XGBoost algorithm predicts the seven-day probability that an agent would adopt the behavior. The per day probability of behavior adoption is derived from the machine learning predicted seven-day probability. 

### Locally Driven Epidemic Awareness

The XGBoost algorithm was trained on data collected during the COVID-19 pandemic, when respondents were already aware of COVID-19 and its risks. As agents in the model are assigned static attributes from this data set—age, gender, working outside the home, perceived severity, and willingness to isolate—they could adopt contact restricting behavior even in the absence of an epidemic. Therefore, we posit agents must first become aware of the epidemic threat before becoming eligible to adopt the behavior. In the model, agents who become infected become aware one day after the start of their infection while awareness also spreads locally from agent to agent along the network. Similar awareness mechanisms have previously been proposed in infectious disease models [5–9]. The probability of a node becoming aware is governed by a logistic function dependent on the proportion of aware neighbors. The growth rate and midpoint parameters can be modified to control how quickly awareness diffuses through the population. 

### Behavioral Fatigue

Agents who adopt the behavior are subject to behavioral fatigue and eventually abandoned the behavior. Prior studies have noted decreased adherence to contact restricting behavior over time, as well as increased mobility in spite of lockdowns [10–13].  Upon behavior adoption, agents are drawn a fatigue time using a Weibull distribution with specified shape (k) and scale (λ) parameters. Shape and scale parameters were parameterized such that 30% of agents fatigue within 28 days (4 weeks) and 100% of agents fatigue within 112 days (16 weeks), with a median fatigue time of 37 days [13]. 

### Behavior Readoption

It was assumed agents who abandon the behavior maintain the ability to readopt the behavior, but this is dependent on present risk within the population as modelled through hospitalizations. Risk is measured through a hospitalization prevalence ratio, wherein the number of hospitalizaitons at time t (Ht) is compared to the historical running maximum hospitalization prevalence (Ht_max) within a given simulation. At the beginning of an epidemic wave when hospitalizations are increasing, the ratio is always equal to one. This prevalence ratio was used as the input variable in a logistic function, with parameters alpha and beta, and determines the probability multiplier for behavioral reuptake, which is then multiplied by the behavior probability as predicted from the XGBoost algorithm. Therefore, when hospitalizations are low, it is unlikely for agents to readopt behavior. 

## References

1.	Alimohamadi Y, Yekta EM, Sepandi M, Sharafoddin M, Arshadi M, Hesari E. Hospital length of stay for COVID-19 patients: a systematic review and meta-analysis. Multidiscip Respir Med. 2022 Aug 9;17(1):856. doi:10.4081/mrm.2022.856 PubMed PMID: 36117876; PubMed Central PMCID: PMC9472334.

2.	RIVM. RIVM [Internet]. [cited 2025 Mar 7]. Covid-19 hospital admissions (according to NICE registration) per municipality per hospital admission date and notification date. Available from: https://data.rivm.nl/meta/srv/dut/catalog.search;jsessionid=15B2AF7C294D70C4EAF5705FE43A774C#/metadata/4f4ad069-8f24-4fe8-b2a7-533ef27a899f

3.	Imperial College London [Internet]. [cited 2025 Sep 19]. COVID-19 behaviour tracker. Available from: https://www.imperial.ac.uk/global-health-innovation/centre-for-health-policy/our-work/covid-19/covid-19-behaviour-tracker/

4.	Chevalier JM, Stellbrink L, Steijvers L, Wijnen S, Daalen F van, Kojan L, et al. Identifying the determinants of health protective behaviors during the COVID-19 pandemic using machine learning: an analysis of six countries. medRxiv; 2026. p. 2026.05.05.26352439. Available from: https://www.medrxiv.org/content/10.64898/2026.05.05.26352439v1 doi:10.64898/2026.05.05.26352439

5.	Perra N, Balcan D, Gonçalves B, Vespignani A. Towards a Characterization of Behavior-Disease Models. PLOS ONE. 2011 Aug 3;6(8):e23084. doi:10.1371/journal.pone.0023084
   
6.	Funk S, Gilad E, Jansen VAA. Endemic disease, awareness, and local behavioural response. J Theor Biol. 2010 May 21;264(2):501–9. doi:10.1016/j.jtbi.2010.02.032
   
7.	Funk S, Gilad E, Watkins C, Jansen VAA. The spread of awareness and its impact on epidemic outbreaks. Proc Natl Acad Sci U S A. 2009 Apr 21;106(16):6872–7. doi:10.1073/pnas.0810762106 PubMed PMID: 19332788; PubMed Central PMCID: PMC2672559.
   
8.	Zhao X, Zhou Q, Wang A, Zhu F, Meng Z, Zuo C. The impact of awareness diffusion on the spread of COVID-19 based on a two-layer SEIR/V–UA epidemic model. J Med Virol. 2021;93(7):4342–50. doi:10.1002/jmv.26945

9.	Zhang HF, Xie JR, Tang M, Lai YC. Suppression of epidemic spreading in complex networks by local information based behavioral responses. Chaos. 2014 Dec;24(4):043106. doi:10.1063/1.4896333 PubMed PMID: 25554026; PubMed Central PMCID: PMC7112481.

10.	Urmi T, Pant B, Dewey G, Quintana-Mathe A, Lang I, Druckman J, et al. Characterizing population-level changes in human behavior during the COVID-19 pandemic in the United States. Proc Natl Acad Sci. 2025 Sep 16;122(37):e2500655122. doi:10.1073/pnas.2500655122

11.	Petherick A, Goldszmidt R, Andrade EB, Furst R, Hale T, Pott A, et al. A worldwide assessment of changes in adherence to COVID-19 protective behaviours and hypothesized pandemic fatigue. Nat Hum Behav. 2021 Sep;5(9):1145–60. doi:10.1038/s41562-021-01181-x PubMed PMID: 34345009.

12.	Stein M, Zacher H, Rudolph CW, Böhm R. Reciprocal within-person relations between pandemic fatigue and protective behavior: A 20-wave longitudinal study during the COVID-19 pandemic. Health Psychol Off J Div Health Psychol Am Psychol Assoc. 2025 Sep 22. doi:10.1037/hea0001551 PubMed PMID: 40991797.

13.	Joshi YV, Musalem A. Lockdowns lose one third of their impact on mobility in a month. Sci Rep. 2021 Nov 22;11:22658. doi:10.1038/s41598-021-02133-1 PubMed PMID: 34811455; PubMed Central PMCID: PMC8608930.









