library("data.table")
library("spdep")
library("sp")
library("PerformanceAnalytics")
library("parallel")
library("rjson")
library("leaflet")
library("rgdal")
library("rgeos")
library("spatialEco")
library("osrm")
library("FNN")
library("dplyr")
library("stringr")
library("shiny")
library("shinythemes")
options(osrm.server = "http://167.114.229.97:5003/")
rm(list=ls())

path <- "~/github/optimal_pos"
Token_map_box <- "https://api.mapbox.com/styles/v1/guillemforto/ck6g8gasf32l41jmkg0956sr5/tiles/256/{z}/{x}/{y}@2x?access_token=pk.eyJ1IjoiZ3VpbGxlbWZvcnRvIiwiYSI6ImNrNjdsYWp6dTE5emIzcG83empsa21teXEifQ.TwcCOiGdCCELzulwTxps0g"

#Projections definition
LIIE <- "+proj=lcc +lat_1=46.8 +lat_0=46.8 +lon_0=0 +k_0=0.99987742 +x_0=600000 +y_0=2200000 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs"
WGS84 <- "+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs"

# ENVIRONMENTS
  # geo1 (INSEE zones)
load(paste(path, "/data/CONTOURS-IRIS_2-1__SHP__FRA_2018-06-08.7z_data_INSEE_IRIS.RData", sep=''))
#return geo1, contient des SPatialpolygons avec des infos
  # market zones (from last session)
load(paste(path, "/data/market_zones.RData", sep=''))
# head(market_zones@data)

  # point of sales data (63 pos)
load(paste(path, "/data/pos_sp.RData", sep=''))
  # customers data
load(paste(path, "/data/cl_sp.RData", sep=''))
  # INSEE Blocs data
load(paste(path, "/data/blocs200m_iris_geometrie_name_geo2_data.RData", sep=''))

# NEW DATA
  # sirene competitors (url : https://data.opendatasoft.com/explore/dataset/sirene_v3%40public/)
  # we consider only competitors of the subsector ("Commerce de détail d'habillement en magasin spécialisé")
load(paste(path, "/data/sirene_competitors.RData", sep=''))
head(sirene)
  # market potential (amount of euros that consumers spent on this market)
load(paste(path, "/data/mp.RData", sep=''))
head(mp)
  # landcover: https://www.statistiques.developpement-durable.gouv.fr/corine-land-cover-0?rubrique=348&dossier=1759
load(paste(path, "/data/landcover.RData", sep=''))
head(landcover@data)

# control
# landcover_523 <- spTransform(subset(landcover, CODE_12=="523")[1,], CRS(WGS84))
# leaflet() %>% addTiles(urlTemplate = Token_map_box, attribution = 'Maps by <a href="http://www.mapbox.com/">Mapbox</a>') %>%
#   addPolygons(data = landcover_523, fillColor = "red", stroke = TRUE, color = "black", opacity = 1, weight = 3, fillOpacity = 0.4)


### DEFINING AN OBJECTIVE FUNCTION ###
# 1. Getting the market share (our principal criteria (not the sales)) from the mp table
order_ <- match(market_zones@data$IRIS, mp$IRIS) # it is the same as a classical merge
market_zones@data$mp <- mp[order_]$mp
market_zones@data$ms <- market_zones@data$sales / market_zones@data$mp # ms is the market share (it must be your Y in Y ~ X + eps)
market_zones@data$ms[which(!is.finite(market_zones@data$ms))] <- 0

# 2. The INSEE IRIS sociodemographic data (already in market_zones)
names(market_zones)

# We pick a subset of these variables to build our predictors later on
subset_INSEE <- c(
  # Caractéristiques des logements
  'P14_LOG', # Nombre de logements
  'P14_LOGVAC', # nombre de logements vacants
  'P14_MAISON', # Nombre de maisons
  'P14_APPART', # Nombre d'appartements
  # Caractéristiques des résidences principales
  'P14_RP', # Nombre de résidence principales
  'P14_RP_3P', # Nombre de résidences principales de 3 pièces
  'P14_RP_4P', # Nombre de résidences principales de 4 pièces
  'P14_RP_5PP', # Nombre de résidences principales de 5 pièces ou plus
  # Caractéristiques des ménages
  'C14_MEN', # nombre de ménages
  'C14_MENPSEUL', # nombre de ménages d'une seule personne
  'C14_MENCOUPSENF', # nombre de ménages dont la famille principale est formée d'un couple sans enfant
  'C14_MENCOUPAENF', # nombre de ménages dont la famille principale est formée d'un couple avec enfant(s)
  # Caractéristiques des personnes
  'P14_POP', # Population
  'P14_PMEN', # nombre de personnes des ménages
  'P14_POPF', # Nombre total de femmes
  'P14_POP65P', # nombre de personnes de 65 ans ou plus
  'C14_POP15P_CS3', # nombre de personnes de 15 ans ou plus Cadres et Professions intellectuelles supérieures
  'C14_POP15P_CS5', # nombre de personnes de 15 ans ou plus Emplyés
  'C14_POP15P_CS8' # nombre de personnes de 15 ans ou plus Autres sans activité
  )

market_zones@data <- market_zones@data[c('IRIS', 'lon', 'lat', 'pos_id', 'minutes', 'ms')]
market_zones@data <- merge(market_zones@data,
                           data.table(geo1@data[,c("IRIS", subset_INSEE)]),
                           by="IRIS")
ncol(market_zones@data) == length(subset_INSEE) + 6 # check


# 3. Competitors from the SIRENE establishments database (this may take 2 mins)
# The objective is to add one column on the market_zones matrix, with the number of competitors
# Because until now we have only market share + minutes + sociodemo
# Remember that we consider sirene as competitors
head(sirene)
# So two simple ways to construct and index:  - over of sirene with the IRIS
#                                             - proximity index

# Lets do the method with over
sirene_sp <- SpatialPointsDataFrame(coords = sirene[,c("longitude","latitude")], data = sirene, proj4string = CRS(WGS84))
# sirene_sp <- SpatialPoints(coords = sirene[,c("longitude","latitude"), with=FALSE],
#                            proj4string = CRS(proj4string(market_zones)))

geo1_WGS84 <- spTransform(geo1, CRS(WGS84))
ov <- over(sirene_sp, geo1_WGS84)

# ov_IRIS <- data.frame(table(ov$IRIS))
agg_ov_IRIS <- aggregate(ov, by=list(ov$IRIS), FUN=length)
competitors <- agg_ov_IRIS[,c('Group.1', 'IRIS')]
colnames(competitors) <- c('IRIS', 'nb_competitors')

market_zones@data <- merge(market_zones@data, competitors, by="IRIS")


# 4.	At least two constraints.
  # get a look at what's inside our dataset before choosing the constraint
head(market_zones@data)
dim(market_zones@data) # 8991 observations, 26 variables

# 4.1 First constraint (e.g. using landcover data)
  # The pos has to be at least 500m away from an airport, a mineral extraction site, a dump site (zone de décharge), or a burnt area
sensible_codes <- c('124', '131', '132', '334')
  # we only keep the coordinates
sensible_areas <- subset(landcover, CODE_12 %in% sensible_codes)
sensible_areas <- spTransform(sensible_areas, CRS(WGS84))
  # quick plot of all sensible zones
leaflet() %>%  addTiles(urlTemplate = Token_map_box, attribution = 'Maps by <a href="http://www.mapbox.com/">Mapbox</a>') %>%
  # airports in blue
  addPolygons(data = subset(sensible_areas, CODE_12 == '124'), fillColor = "blue", stroke = TRUE, color = "blue", opacity = 1, weight = 3, fillOpacity = 0.4) %>%
  # mineral extraction sites in purple
  addPolygons(data = subset(sensible_areas, CODE_12 == '131'), fillColor = "purple", stroke = TRUE, color = "purple", opacity = 1, weight = 3, fillOpacity = 0.4) %>%
  # dump sites in brown
  addPolygons(data = subset(sensible_areas, CODE_12 == '132'), fillColor = "brown", stroke = TRUE, color = "brown", opacity = 1, weight = 3, fillOpacity = 0.4) %>%
  # burnt areas in black
  addPolygons(data = subset(sensible_areas, CODE_12 == '334'), fillColor = "black", stroke = TRUE, color = "black", opacity = 1, weight = 3, fillOpacity = 0.4)

  # adding the columns to our market_zones
ov <- over(sensible_areas, geo1_WGS84)
agg_ov_IRIS <- aggregate(ov, by=list(ov$IRIS), FUN=length)
candidates <- agg_ov_IRIS[,c('Group.1', 'IRIS')]
colnames(candidates) <- c('IRIS', 'nb_sensible_areas')

market_zones@data <- merge(market_zones@data, candidates, by="IRIS", all.x=TRUE) # left outer join
market_zones@data$nb_sensible_areas[is.na(market_zones@data$nb_sensible_areas)] <- 0



# 4.2 Second constraint
  # Ex: The pos has to be in a 'carreau' where at least 61 (9th decile of geo2_data$ind_c) people reside

subset_geo2_data <- subset(geo2_data, ind_c > quantile(geo2_data$ind_c, c(0.90)))

#certaines lignes peuvent prendre plusieurs minutes pour tourner
geo2_data_sp <- SpatialPointsDataFrame(coords = subset_geo2_data[,c("lon","lat")],data = subset_geo2_data, proj4string = CRS(WGS84))
geo2_data_sp_LIIE <- spTransform(geo2_data_sp,CRS(LIIE))
geo2_data_sp_LIIE_blocs <- gBuffer(spgeom = geo2_data_sp_LIIE,byid = TRUE,width = 100,capStyle = "SQUARE")
blocs_WGS84 <- spTransform(gBuffer(spgeom = geo2_data_sp_LIIE_blocs,byid = TRUE,width = 100,capStyle = "SQUARE"),CRS(WGS84))
blocs_WGS84 <- spChFIDs(blocs_WGS84,as.character(blocs_WGS84$idgeo2))


coord_points <- SpatialPointsDataFrame(data = market_zones@data[,c('lon','lat')],coords = market_zones@data[,c('lon','lat')],
                        proj4string = CRS(WGS84))

res <- over(coord_points, blocs_WGS84)
w <- which(!is.na(res$idgeo2))
length(w)

# on ajoute la vérification ou non de la seconde contrainte comme nouvelle colonne dans le dataset
market_zones@data$second_constraint <- FALSE
market_zones@data$second_constraint[w] <- TRUE



### MODEL ###
# Model preparation: building some new variables of interest
get_variables_of_interest <- function(df){
  # Caractéristiques des logements
  df$prop_LOGVAC = df$P14_LOGVAC / df$P14_LOG
  df$prop_MAISON = df$P14_MAISON / df$P14_LOG
  df$prop_APPART = df$P14_APPART / df$P14_LOG
  # Caractéristiques des résidences principales
  df$prop_RP_3PP = (df$P14_RP_3P + df$P14_RP_4P + df$P14_RP_5PP) / df$P14_RP
  df$prop_RP_5PP = df$P14_RP_5PP / df$P14_RP
  # Caractéristiques des ménages
  df$prop_MENPSEUL = df$C14_MENPSEUL / df$C14_MEN
  df$prop_MENCOUPSENF = df$C14_MENCOUPSENF / df$C14_MEN
  df$prop_MENCOUPAENF = df$C14_MENCOUPAENF / df$C14_MEN
  # Caractéristiques des personnes
  df$prop_PMEN = df$P14_PMEN / df$P14_POP
  df$prop_POPF = df$P14_POPF / df$P14_POP
  df$prop_POP65P = df$P14_POP65P / df$P14_POP
  df$prop_POP15P_CS3 = df$C14_POP15P_CS3 / df$P14_POP
  df$prop_POP15P_CS5 = df$C14_POP15P_CS5 / df$P14_POP
  df$prop_POP15P_CS8 = df$C14_POP15P_CS8 / df$P14_POP

  return(df)
}

market_zones@data <- get_variables_of_interest(market_zones@data)


variables_to_model <- c('ms', 'minutes', 'nb_competitors',
                        'prop_LOGVAC', 'prop_MAISON', 'prop_APPART',
                        'prop_RP_3PP', 'prop_RP_5PP', 'prop_MENPSEUL', 'prop_MENCOUPSENF',
                        'prop_PMEN', 'prop_POPF', 'prop_POP65P', 'prop_POP15P_CS3', 'C14_POP15P_CS5', 'prop_POP15P_CS8')
model_dataset <- market_zones@data[variables_to_model]
model_dataset <- na.omit(model_dataset)

# We build a spatial interaction model based on the in-sample matrix in order to predict the market share
LM1 <- lm(ms ~ log(minutes + 0.001) + ., data = model_dataset)
summary(LM1)
plot(LM1)
summary(market_zones@data)






# 5. At least 10 spatial positions for the candidate points.  (Difficult part)
# You need to apply MODEL (LM1) to the 10 new positions
# You need to construct the market_zones matrix of the new 10 points
nb_candidate_points = 10
set.seed(123) # to get always the same sample (one without failing points)
new_positions <- sirene_sp[sample(1:length(sirene_sp), nb_candidate_points),]


# For the 10 new_positions:
# 1. contruct their market_zones matrix
# 2. apply the LM1 model
# 3. based on your constraints what is the best and worst area

get_market_zone_for_competitor <- function(i) {
  # i will go from 1:nb_candidate_points
  ith_competitor_position <- coordinates(spTransform(new_positions[i,], CRS(LIIE)))

  # We get all geo1 variables of the 1000 closest (euclid dist) IRIS to the ith_competitor_position.
  # This creates a market zone
  IRIS_positions <- data.frame(coordinates(spTransform(SpatialPoints(coords = geo1@data[,c("lon","lat")], proj4string = CRS(WGS84)), CRS(LIIE))))
  colnames(IRIS_positions) <- c("x","y")
  new_market_zone <- geo1@data[c(get.knnx(data = IRIS_positions,
                                          query = ith_competitor_position, k = 1000)$nn.index),]
  # l'object ci-dessus est bien de taille 1000

  # socio-demographic
  new_market_zone <- new_market_zone[,c('IRIS', 'lon', 'lat', subset_INSEE)]

  # competitors (c'est cette ligne qui fait qu'on a pas 2000 obs par pos_id)
  new_market_zone <- merge(new_market_zone, competitors, by="IRIS")

  # minutes (traveling time)
    # the origins are the customers
  origin <- new_market_zone[,c("IRIS","lon","lat")]
  setnames(origin, c("id","x","y"))
    # the destination is the ith point of sales
  destination <- data.frame(id=paste("new_pos_",i,sep=""), coordinates(new_positions[i,]))
  setnames(destination,c("id","x","y"))
    # now we can get the 2000 traveling times
  new_market_zone$minutes <- c(osrmTable(src = data.frame(origin), dst = data.frame(destination))$durations) / 60
  # new_market_zone <- new_market_zone[which(new_market_zone$minutes < 35),] # limit of 35 minutes

  # variables of interest
  new_market_zone <- get_variables_of_interest(new_market_zone)

  # add index new_pos_i
  new_pos_i <- paste("new_pos_", i, sep="")
  new_market_zone$posid <- new_pos_i

  return(new_market_zone)
}

# for the 10 selected competitors
all_new_market_zones <- data.frame()
for (i in 1:length(new_positions)) {
  print(i)
  all_new_market_zones <- rbind(all_new_market_zones, get_market_zone_for_competitor(i))
}
# if the for failed, rerun part 5 until you pick 10 new points that hopefully won't contain lat lon issues
# View(all_new_market_zones)

# Applying LM1
all_new_market_zones$market_share_predicted <- predict(LM1, newdata = all_new_market_zones)

# The two constraints
  # First constraint
# add the nb of sensible areas from market zones
new_positions_LIIE <- spTransform(new_positions, CRS(LIIE))
new_positions_buffer <- gBuffer(spgeom = new_positions_LIIE, byid=TRUE, width = 10000)
new_positions_buffer <- spTransform(new_positions_buffer, CRS(WGS84))

leaflet() %>%  addTiles() %>%
  addPolygons(data = new_positions_buffer, fillColor = "blue", stroke = TRUE, color = "blue", opacity = 1, weight = 3, fillOpacity = 0.4) %>%
  addPolygons(data = sensible_areas, fillColor = "red", stroke = TRUE, color = "red", opacity = 1, weight = 3, fillOpacity = 0.4)

for (i in 1:length(new_positions)){
  print(i)
  ov2 <- over(new_positions_buffer[i,], sensible_areas, returnList = TRUE)
  new_positions$nbr_sensible_areas[i]<-nrow(ov2[[1]])
}


  ## Second constraint
res_new <- over(new_positions[,c('longitude','latitude')], blocs_WGS84)
w_new <- which(!is.na(res_new$idgeo2))
length(w_new)
new_positions$second_constraint <- FALSE
new_positions$second_constraint[w_new] <- TRUE




# add the predicted market shares
predicted_market_zones <- select(all_new_market_zones, posid, market_share_predicted)
predicted_market_zones$market_share_predicted[is.na(predicted_market_zones$market_share_predicted)]<-0

# add sum of market shares
sum_market_zones <- aggregate(predicted_market_zones$market_share_predicted, by=list(posid=predicted_market_zones$posid), FUN=sum)
sum_market_zones$posid <- str_sub(sum_market_zones$posid,start=-1)
for (i in 1:length(new_positions)){
  print(i)
  new_positions$sum_market[i]<-filter(sum_market_zones, posid == i-1)$x
}

# add count of competitors
count_market_zones<-aggregate(predicted_market_zones$market_share_predicted, by=list(posid=predicted_market_zones$posid), FUN=length)
count_market_zones$posid<-str_sub(count_market_zones$posid,start=-1)
for (i in 1:length(new_positions)){
  print(i)
  new_positions$count_market[i]<-filter(count_market_zones, posid == i-1)$x
}

best <- new_positions[which.max(new_positions$sum_market),]
worst <- new_positions[which.min(new_positions$sum_market),]


leaflet_project <- leaflet() %>%  addTiles(urlTemplate = Token_map_box) %>%
  addCircleMarkers(data=new_positions, radius = ~sum_market,
                   stroke = TRUE, color = "blue", opacity = 0.8,
                   labelOptions = labelOptions(noHide = T,
                                               direction = 'top',
                                               offset=c(0,0),
                                               textOnly = TRUE,
                                               style=list('color'='rgba(0,0,0,1)','font-family'= 'Arial Black','font-style'= 'bold',
                                                          'box-shadow' = '0px 0px rgba(0,0,0,0.25)','font-size' = '6px',
                                                          'background-color'='rgba(255,255,255,0.7)','border-color' = 'rgba(0,0,0,0)')))%>%
  addCircleMarkers(data = best,color="green", group = "best_worst")%>%
  addCircleMarkers(data = worst,color="red", group = "best_worst")
leaflet_project

save(leaflet_project, file=paste(path, "/deployment/www/leaflet_project.RData", sep=''))
# load(paste(path, "/deployment/www/leaflet_project.RData", sep=''))

# deployment
ui <- bootstrapPage(
  tags$style(type = "text/css", "html, body {width:100%;height:100%}"),
  leafletOutput("Map", width = "100%", height = "100%"),
  absolutePanel(id = 'panel',
                bottom = 20, left = 20, style="z-index:500; opacity:0.95; background-color:rgba(192,192,192,.5)", draggable = FALSE,
                h3("Choose the characteristics"),
                sliderInput("competitors", label="Number of competitors:",
                            min=0, max=max(new_positions$count_market), value=c(0,1464), step=100, width=280),
                sliderInput("sensible_areas",label="Number of sensible areas in the perimeter:",
                            min=0, max=max(new_positions$nbr_sensible_areas), value=c(0,3), step=1, width=280),
                checkboxInput("second_constraint", "Population constraint respected", TRUE),
                checkboxGroupInput("employees", label = "Number of employees:",
                                   choices = list("No employees" = 'NN', "0 employees" = "0", "1 or 2 employees" = 2, "3 to 5 employees" = 3),
                                   selected = c("NN","0","1","2","3")),
                h6('Size of the points is proportional to the'),
                h6('sum of the market shares of the competitors.')
))


server<-function(input, output, session) {

  san<-reactive({
    subset(new_positions,new_positions$count_market>=input$competitors[1]&
                         new_positions$count_market<=input$competitors[2]&
                         new_positions$nbr_sensible_areas>=input$sensible_areas[1]&
                         new_positions$nbr_sensible_areas<=input$sensible_areas[2]&
                         new_positions$EFETCENT %in% input$employees&
                         new_positions$second_constraint == input$second_constraint)
                })

  output$Map <- renderLeaflet({leaflet_project})

  observe({
    leafletProxy("Map",data=san()) %>%
      clearMarkers() %>%
      addCircleMarkers(data=san(), radius = ~sum_market,
                       stroke = TRUE, color = "blue", opacity = 0.8,
                       labelOptions = labelOptions(noHide = T,
                                                   direction = 'top',
                                                   offset=c(0,0),
                                                   textOnly = TRUE,
                                                   style=list('color'='rgba(0,0,0,1)', 'font-family' = 'Arial Black', 'font-style' = 'bold',
                                                              'box-shadow' = '0px 0px rgba(0,0,0,0.25)', 'font-size' = '6px',
                                                              'background-color'='rgba(255,255,255,0.7)', 'border-color' = 'rgba(0,0,0,0)'))) %>%
      addCircleMarkers(data = best, color="green", group = "best_worst")%>%
      addCircleMarkers(data = worst, color="red", group = "best_worst")
      })
}

shinyApp(ui = ui, server = server)
