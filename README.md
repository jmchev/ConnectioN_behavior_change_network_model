# ConnectioN Project: Agent-based model with machine learning driven behavioral change

This agent-based model was developed in R (4.4.2) for the purpose of pandemic preparedness and response under funding from ZonMw (Netherlands Organization for Health Research and Development; Project number: 10710062310022) at University Medical Center Utrecht. 

The agent-based model utilizes the XGBoost (eXtreme Gradient Boosting—produces an ensemble of gradient-boosted decision trees) machine learning algorithm (R library: xgboost) to predict agent health behavior at each time-step (day) based on assigned agent characteristics (age, gender, perceived COVID-19 severity, willingness to isolate (if directed by health authority), working outside the home (non-remote)), and the modelled number of COVID-19 hospitalizations at time t.

The XGBoost model was trained on survey data obtained for the Netherlands available from the Imperial College London & YouGov COVID-19 Behavior Tracker Hub (https://github.com/YouGov-Data/covid-19-tracker). XGBoost hyperparameter tuning and algorithm training are conducted in "Train_xgb_network_model.R" using "nl_yougov_data.rds". The analysis period was 24 June 2020 – 13 January 2021. The full, unfiltered data can be found in the CSV file "nl_yougov_data.csv". For further details on data and analysis please see [10].

The network model utilizes underlying synthetic network structures (small world, random, preferential attachment) to represent the daily contacts among modelled agents (N=10,000) in "Construct_synthetic_networks.R". Agents are assigned characteristics from "nl_yougov_data.rds". 

"SIHR_Network_Function.R" contains the model code. The model cycles over the number of time steps specified (days). Epidemiologically, agents exist in susceptible, infectious, hospitalized, and recovered (SIHR) states. Recovered agents remain immune for the duration of the model and hospitalized agents do not contribute to infections. Behaviorally, agents can be unaware of the epidemic, aware of the epidemic but not practicing behavior, aware of the epidemic and practicing behavior, aware of the epidemic and fatigued from behavior, aware of the epidemic and practicing behavior following re-adoption. Behavioral agents cease physical contact, and therefore infection potential, with 47% of their network members for the duration of behavior. See "model_flow_diagram.pdf" for a visual representation of model processes. 

The model is set-up to run simulations in parallel. All necessary functions, parameters, and dependencies are initialized in "Run_behavior_network_model.R" and passed to "Network_model_parallel_function.R". 

Please see below for further detail on methodology. 

Connection consortium collaborators include: Joshua M Chevalier (model author; UMC Utrecht), Leonard Stellbrink (University of Luebeck), Florian van Daalen (Maastrict University), Lisanne Steijvers (Maastrict University), Senne Wijnen (Maastrict University), Lilian Kojan (University of Luebeck), Nannan Li (Maastrict University), Beate Jahn (UMIT TIROL), Uwe Siebert (UMIT TIROL), André Calero Valdez (University of Luebeck), Mickaël Hiligsmann (Maastrict University), Rik Crutzen (Maastrict University), Nicole Dukers-Muijrers (GGD-Zuid Limburg, Maastricht University), Mirjam Kretzschmar (consortium lead; UMC Utrecht, University of Munster) 


## Methods (from manuscript): 

### SIHR Transmission Model

In the epidemic simulation, agents could exist in susceptible, infectious, hospitalized, and recovered disease states (SIHR model). The epidemic transmission parameters are shown in Table 2. The base case transmission probability was calculated from data that observed an early SARS-CoV-2 reproduction number of 3.3 [1,2]. Assuming the basic reproduction number (R0) is the product of the average daily contact rate (10 contacts/day) [3,4], the duration of infectivity (10 days) [5,6], and the probability of transmission per contact, an R0 of 3.3 produces a transmission probability of 0.033 per contact. Basic reproduction numbers of 2.5 and 4.0 were also considered, producing transmission probabilities of 0.025 and 0.040, respectively. As this calculation relies on an average contact rate, it is not reflective of the observed reproduction number on a small world network. The hospitalization probability was estimated through Bayesian computation using RStan (version 2.32.7), with a basic SIHR compartmental model, assuming a duration of hospitalization of 15 days [7], and fitted to Netherlands COVID-19 hospital admissions data from 2020 [8]. Two randomly infected agents were used to initialize the epidemic in each simulation.


### Contact Restricting Behavior

Agents could adopt contact restricting (social distancing) behavior in response to the epidemic. Contact restricting behavior was derived from publicly available secondary data—the Imperial College London and YouGov COVID-19 Behavior Tracker Survey data [9]. The behavior survey was conducted from April 2020–March 2022 in 29 different countries. We extracted the survey data from the Netherlands for the period June 2020–January 2021, prior to widespread vaccination. The survey asked participants four questions related to social distancing: frequency of avoiding 1) small (<3 people), 2) medium (3–10 people), and 3) large social gatherings (>10 people), or 4) crowds over the previous 7-day period. Questions were answered on a five-point Likert scale and responses were summed into a composite social distancing score with range 4–20. The score was converted into a binary variable where a score >16 (average response of 4: “frequently” to each question) was used to represent social distancing (binary value of one). Survey respondents also reported their household size and the number of contacts they had outside the home in the previous 7 days, which were used to estimate the network size of respondents. Respondents with a score >16 reported 47% less contacts from outside the home, on average, compared to those with a score <16. 

The model assumed all or nothing behavioral participation (contact restricting versus no contact restricting) and when agents adopted behavior 47% of their connections to other agents—referred to as edges—were temporarily inactivated. Inactivation of edges was a random stochastic process that occurred at the time of behavior adoption where each edge had a 47% chance of becoming inactive when either agent adopted behavior. Edge inactivation was not completely symmetric—if an agent adopted behavior, but neighboring agents already inactivated their edges to that agent, all remaining edges still had a 47% probability of being inactivated. Conversely, if an edge between two behavioral agents was inactive, the edge could be reactivated if either agent abandoned the behavior. Edges were only reduced with respect to physical contact, preventing infection, but did not impact the ability of epidemic awareness to spread between agents.


### Machine Learning Predicted Behavioral Adoption

The XGBoost algorithm was trained on the Imperial College London YouGov COVID-19 Behavior Tracker Survey data from the Netherlands, which was combined with COVID-19 hospitalization data by date from the National Institute of Public Health and the Environment (RIVM) for the analysis period June 2020 to January 2021 [8,9]. In the previous analysis, XGBoost was trained on the same behavioral survey and hospitalization data to identify the top predictors of social distancing behavior (out of 24 variables) in eight countries [10]. The top three predictors of social distancing behavior in the Netherlands were a participant’s reported willingness to self-isolate (assuming COVID-19 symptoms) if advised to do so by a public health authority (asked on a 5-point Likert scale in the survey), their perceived severity to COVID-19 (asked on a 7-point Likert scale), and the number of COVID-19 hospitalizations per 100,000 within the country at the time of the survey. Based on these prior results, a simplified XGBoost algorithm was trained using only agent demographics and the top predictors of social distancing behavior: age (continuous), gender (binary), perceived severity (continuous), willingness to isolate (continuous), COVID-19 hospitalizations per 100,000 (continuous), and working outside the home (none-remote work; binary). The algorithm was trained using a “binary:logistic” log loss function and hyperparameters were optimized for the data using parallel Bayesian optimization with five-fold cross validation. Predictor importance was assessed using SHAP values (SHapely Additive exPlanations), which are calculated per predictor per data observation. SHAP values represent the marginal contribution of a predictor to the log odds of contact restricting behavior for a given observation.

To link the agents in the model to the XGBoost predicted contact restricting behavior, agents were assigned values of the predictor variables directly from the behavioral survey data. Each agent was assigned the age (18–99), gender, perceived severity score (1–7), willingness to isolate score (1–5), and remote working status of a single survey respondent from the Imperial College London YouGov COVID-19 Behavior Tracker Survey data, thereby maintaining any correlations between variables. Agents with the greatest number of connections (degree) were assigned the attributes from survey respondents with the greatest reported network size—calculated as the sum of household members and the average daily number of reported contacts from outside the home. 

The trained XGBoost model was then integrated into the epidemic simulation and, using agent attributes and the hospitalizations at time t, estimated the 7-day probability that an agent would adopt contact restricting behavior (P_xg). The 7-day probability was then converted into a per day probability (P_behavior):

P_behavior = 1 - (1 - P_xg)^(1/7) × P_readopt
 

### Locally Driven Epidemic Awareness

The XGBoost algorithm was trained on data collected during the COVID-19 pandemic, when the presence of and risks associated with SARS-CoV-2 infection were already widely communicated to the public. As agent attributes were static, they could adopt contact restricting behavior even in the absence of an epidemic. Therefore, we assumed agents had to first become aware of the epidemic before becoming eligible to adopt the behavior. In the model, agents who became infected became aware one day after the start of their infection. Awareness also spread locally from agent to agent along the network. Similar awareness mechanisms have previously been proposed in infectious disease models [11-15]. The probability of an agent becoming aware (P_awareness) was governed by a logistic function dependent on the proportion of aware neighbors (a/n). The growth rate (α_1) and midpoint (β_1) parameters of the function controlled how quickly awareness spread through the population. 

P_awareness = 1 / (1 + e^(-α_1 × ((a/n)  - β_1)))


### Behavioral Fatigue

Agents who adopt the behavior are subject to behavioral fatigue and eventually abandoned the behavior. Prior studies have noted decreased adherence to contact restricting behavior over time, as well as increased mobility in spite of lockdowns [16–19].  Upon behavior adoption, agents are drawn a fatigue time using a Weibull distribution with specified shape (k) and scale (λ) parameters. Shape and scale parameters were parameterized such that 30% of agents fatigue within 28 days (4 weeks) and 100% of agents fatigue within 112 days (16 weeks), with a median fatigue time of 37 days [19]. 

T_fatigue = λ × (-ln(U))^(1/k) where U~(0,1) and represents the quantile of the popualtion.


### Behavior Readoption

It was assumed agents who abandon the behavior maintain the ability to readopt the behavior, but this is dependent on present risk within the population as modelled through hospitalizations. Risk was measured through a hospitalization prevalence ratio, wherein the number of hospitalizations at time t (Ht) is compared to the historical running maximum hospitalization prevalence (Ht_max) within a given simulation. At the beginning of an epidemic wave when hospitalizations were increasing, the ratio was always equal to one. This prevalence ratio was used as the input variable in a logistic function, with parameters alpha (α_2) and beta (β_2), and determines the probability multiplier for behavioral reuptake, which was then multiplied by the behavior probability as predicted from the XGBoost algorithm. Therefore, when hospitalizations are low, it is unlikely for agents to readopt behavior. 

P_readopt = 1 / (1 + e^(-α_2 × ((Ht/Ht_max) - β_2)))


## References

1. Billah MA, Miah MM, Khan MN. Reproductive number of coronavirus: A systematic review and meta-analysis based on global level evidence. PLOS ONE. 2020 Nov 11;15(11):e0242128. doi:10.1371/journal.pone.0242128
   
2. Liu Y, Gayle AA, Wilder-Smith A, Rocklöv J. The reproductive number of COVID-19 is higher compared to SARS coronavirus. J Travel Med. 2020 Feb 13;27(2):taaa021. doi:10.1093/jtm/taaa021 PubMed PMID: 32052846; PubMed Central PMCID: PMC7074654.
   
3. Backer JA, Mollema L, Vos ER, Klinkenberg D, van der Klis FR, de Melker HE, et al. Impact of physical distancing measures against COVID-19 on contacts and mixing patterns: repeated cross-sectional surveys, the Netherlands, 2016-17, April 2020 and June 2020. Euro Surveill Bull Eur Sur Mal Transm Eur Commun Dis Bull. 2021 Feb;26(8):2000994. doi:10.2807/1560-7917.ES.2021.26.8.2000994 PubMed PMID: 33632374; PubMed Central PMCID: PMC7908067.
   
4. Mossong J, Hens N, Jit M, Beutels P, Auranen K, Mikolajczyk R, et al. Social Contacts and Mixing Patterns Relevant to the Spread of Infectious Diseases. PLOS Med. 2008 Mar 25;5(3):e74. doi:10.1371/journal.pmed.0050074

5. Walsh KA, Spillane S, Comber L, Cardwell K, Harrington P, Connell J, et al. The duration of infectiousness of individuals infected with SARS-CoV-2. J Infect. 2020 Dec;81(6):847–56. doi:10.1016/j.jinf.2020.10.009 PubMed PMID: 33049331; PubMed Central PMCID: PMC7547320.

6. Byrne AW, McEvoy D, Collins AB, Hunt K, Casey M, Barber A, et al. Inferred duration of infectious period of SARS-CoV-2: rapid scoping review and analysis of available evidence for asymptomatic and symptomatic COVID-19 cases [Internet]. 2020 Aug 1. doi:10.1136/bmjopen-2020-039856

7.	Alimohamadi Y, Yekta EM, Sepandi M, Sharafoddin M, Arshadi M, Hesari E. Hospital length of stay for COVID-19 patients: a systematic review and meta-analysis. Multidiscip Respir Med. 2022 Aug 9;17(1):856. doi:10.4081/mrm.2022.856 PubMed PMID: 36117876; PubMed Central PMCID: PMC9472334.

8.	RIVM. RIVM [Internet]. [cited 2025 Mar 7]. Covid-19 hospital admissions (according to NICE registration) per municipality per hospital admission date and notification date. Available from: https://data.rivm.nl/meta/srv/dut/catalog.search;jsessionid=15B2AF7C294D70C4EAF5705FE43A774C#/metadata/4f4ad069-8f24-4fe8-b2a7-533ef27a899f

9.	Imperial College London [Internet]. [cited 2025 Sep 19]. COVID-19 behaviour tracker. Available from: https://www.imperial.ac.uk/global-health-innovation/centre-for-health-policy/our-work/covid-19/covid-19-behaviour-tracker/

10.	Chevalier JM, Stellbrink L, Steijvers L, Wijnen S, Daalen F van, Kojan L, et al. Identifying the determinants of health protective behaviors during the COVID-19 pandemic using machine learning: an analysis of six countries. medRxiv; 2026. p. 2026.05.05.26352439. Available from: https://www.medrxiv.org/content/10.64898/2026.05.05.26352439v1 doi:10.64898/2026.05.05.26352439

11.	Perra N, Balcan D, Gonçalves B, Vespignani A. Towards a Characterization of Behavior-Disease Models. PLOS ONE. 2011 Aug 3;6(8):e23084. doi:10.1371/journal.pone.0023084
   
12.	Funk S, Gilad E, Jansen VAA. Endemic disease, awareness, and local behavioural response. J Theor Biol. 2010 May 21;264(2):501–9. doi:10.1016/j.jtbi.2010.02.032
   
13.	Funk S, Gilad E, Watkins C, Jansen VAA. The spread of awareness and its impact on epidemic outbreaks. Proc Natl Acad Sci U S A. 2009 Apr 21;106(16):6872–7. doi:10.1073/pnas.0810762106 PubMed PMID: 19332788; PubMed Central PMCID: PMC2672559.
   
14.	Zhao X, Zhou Q, Wang A, Zhu F, Meng Z, Zuo C. The impact of awareness diffusion on the spread of COVID-19 based on a two-layer SEIR/V–UA epidemic model. J Med Virol. 2021;93(7):4342–50. doi:10.1002/jmv.26945

15.	Zhang HF, Xie JR, Tang M, Lai YC. Suppression of epidemic spreading in complex networks by local information based behavioral responses. Chaos. 2014 Dec;24(4):043106. doi:10.1063/1.4896333 PubMed PMID: 25554026; PubMed Central PMCID: PMC7112481.

16.	Urmi T, Pant B, Dewey G, Quintana-Mathe A, Lang I, Druckman J, et al. Characterizing population-level changes in human behavior during the COVID-19 pandemic in the United States. Proc Natl Acad Sci. 2025 Sep 16;122(37):e2500655122. doi:10.1073/pnas.2500655122

17.	Petherick A, Goldszmidt R, Andrade EB, Furst R, Hale T, Pott A, et al. A worldwide assessment of changes in adherence to COVID-19 protective behaviours and hypothesized pandemic fatigue. Nat Hum Behav. 2021 Sep;5(9):1145–60. doi:10.1038/s41562-021-01181-x PubMed PMID: 34345009.

18.	Stein M, Zacher H, Rudolph CW, Böhm R. Reciprocal within-person relations between pandemic fatigue and protective behavior: A 20-wave longitudinal study during the COVID-19 pandemic. Health Psychol Off J Div Health Psychol Am Psychol Assoc. 2025 Sep 22. doi:10.1037/hea0001551 PubMed PMID: 40991797.

19.	Joshi YV, Musalem A. Lockdowns lose one third of their impact on mobility in a month. Sci Rep. 2021 Nov 22;11:22658. doi:10.1038/s41598-021-02133-1 PubMed PMID: 34811455; PubMed Central PMCID: PMC8608930.









