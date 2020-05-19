# Optimal point of sales

We built a [Shiny app](https://shiny.rstudio.com) to find the optimal point of sales in a spatial dataset.

**Authors:** Guillem FORTO / Caroline LEBRUN / Madeleine SMANIOTTO

**Date:** March - April 2020<br>
This project was part of the Geomarketing course of the M2 Statistics and Econometrics, at Toulouse School of Economics.

## Table of contents
* [Description](#description)
* [Output](#output)
* [Additional information](#additional-information)
    * [1. Datasets](#1-datasets)
    * [2. Socioeconomic variables](#2-socioeconomic-variables)



## Description
The main idea was to build a spatial interaction model capable of predicting the market share of multiple point of sales. Here are the steps we followed:
- Assembled all the features that are necessary to build a spatial interaction model on market zones in a single dataframe. Predictors included:
    - [INSEE IRIS](#1-datasets) socioeconomic data
    - travelling time in minutes between market zones
    - data on the number of competitors, extracted from the [SIRENE](#1-datasets) establishments database


- Added two constraints to the model to add some restrictions (see image below)

At this point, the objective function, subject to the two constraints, could be written as follows:

![](objective_func.png "Objective function and its contraints")


- Once the model built, we applied it to at least 10 new randomly picked candidate shops from the SIRENE dataset. The one with the largest market share is then defined as the optimal position.

- Implemented everything on an interactive Shiny app that shows at least the best and the worst market zone, with at least one widget that explains the socioeconomic/competitors characteristics of each the zone.

## Output
The output tables for the 10 candidates looks like this:
- Best candidate

| SIREN | NIC | ... | longitude | latitude | geo_score | nbr_sensible_areas | second_constraint | sum_market | count_market |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 530487263 | 10 | ... | 2.674524 | 45.86835 | 0.65 | 0 | TRUE | 2.705042 | 843 |

- Worst candidate

| SIREN | NIC | ... | longitude | latitude | geo_score | nbr_sensible_areas | second_constraint | sum_market | count_market |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 332855691 | 207 | ... | 2.332238 | 48.87019 | 0.94 | 0 | TRUE | 0.2029933 | 578 |

and the RShiny application:

![](rshinyapp.png "Shiny app first look")

The green location is considered to be the best, and the red one the worst. Also, as you move the cursors and change the constraints, the 10 points automatically update on the map.

## Additional information
##### 1. Datasets
- IRIS (Ilots Regroupés pour l'Information Statistique) is a data set provided by [INSEE](https://www.insee.fr/fr/accueil), the national statistics bureau of France, with the aim of making geolocalized data about the French communes publicly available. It provides socio-demographic through a homogeneously grided zoning of the French territory.
- [SIRENE](https://www.data.gouv.fr/en/datasets/base-sirene-des-entreprises-et-de-leurs-etablissements-siren-siret/) is a data set on companies and its characteristics. See also this [interactive platform]( https://data.opendatasoft.com/explore/dataset/sirene_v3%40public/?disjunctive.libellecommuneetablissement&disjunctive.etatadministratifetablissement&disjunctive.sectionetablissement&disjunctive.naturejuridiqueunitelegale&sort=datederniertraitementetablissement).
- [Landcover](https://www.statistiques.developpement-durable.gouv.fr/corine-land-cover-0?rubrique=348&dossier=1759) is a European data set. It constitutes 'biophysical land use inventory which provides a complete picture of land use, at regular frequencies'.


##### 2. Socioeconomic variables

- Housing characteristics

| Name          | Description |
| ------------- |-------------|
| P14_LOG       | Nombre de logements |
| P14_LOGVAC    | Nombre de logements vacants |
| P14_MAISON    | Nombre de maisons |
| P14_APPART    | Nombre d'appartements |

- Characteristics of main residences

| Name          | Description |
| ------------- |-------------|
| P14_RP       | Nombre de résidence principales |
| P14_RP_3P       | Nombre de résidences principales de 3 pièces |
| P14_RP_4P       | Nombre de résidences principales de 4 pièces |
| P14_RP_5PP       | Nombre de résidences principales de 5 pièces ou plus |

- Household characteristics

| Name          | Description |
| ------------- |-------------|
| C14_MEN       | Nombre de maisons |
| C14_MENPSEUL       | Nombre de maisons |
| C14_MENCOUPSENF       | Nombre de maisons |
| C14_MENCOUPAENF       | Nombre de maisons |

- People characteristics

| Name          | Population |
| ------------- |-------------|
| P14_POP       | Nombre de maisons |
| P14_PMEN       | Nombre de personnes des ménages |
| P14_POPF       | Nombre total de femmes |
| P14_POP65P       | Nombre de personnes de 65 ans ou plus |
| C14_POP15P_CS3       | Nombre de personnes de 15 ans ou plus Cadres et Professions intellectuelles supérieures |
| C14_POP15P_CS5       | Nombre de personnes de 15 ans ou plus Employés |
| C14_POP15P_CS8       | Nombre de personnes de 15 ans ou plus Autres sans activité |
