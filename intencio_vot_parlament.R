# ORIGINAL AQUÍ https://github.com/ceopinio/estimacions/blob/main/EstimacioBOP22_1_v3.do

## Això és una traducció de stata. Hi ha possibles errors, per tant, no em faig responsable dels resultats

library(tidyverse)
library(haven)
library(mlogit)

library(weights)
library(tidymodels)
library(workflows)
# llegir dades

dataset = read_sav("./Microdades anonimitzades 1019.sav")

# parlament

# Preparem record de vot per ponderació


# Unim nul, blanc i abst (BAN)
dataset <- dataset |>
  mutate("REC_PARLAMENT_VOT_CENS_R_old" = REC_PARLAMENT_VOT_CENS_R,
         "REC_PARLAMENT_VOT_CENS_R" = case_when(as.numeric(REC_PARLAMENT_VOT_CENS_R) %in% c(93, 94) ~ 96,
                                                TRUE ~ as.numeric(REC_PARLAMENT_VOT_CENS_R)))

# Calculem la variable de ponderació (vot real 14F2021/record de vot declarat, excloent els NS/NC)


dataset <- dataset |>
  mutate("pondrvot" = case_when(REC_PARLAMENT_VOT_CENS_R == 1 ~ 1.304222092, # PPC
                                REC_PARLAMENT_VOT_CENS_R == 3 ~ 0.471791685, # ERC
                                REC_PARLAMENT_VOT_CENS_R == 4 ~ 0.953111487, # PSC
                                REC_PARLAMENT_VOT_CENS_R == 6 ~ 1.754926015, # C'S
                                REC_PARLAMENT_VOT_CENS_R == 10 ~ 0.668643161, # CUP
                                REC_PARLAMENT_VOT_CENS_R == 21 ~ 1.141610892, # JXCAT
                                REC_PARLAMENT_VOT_CENS_R == 22 ~ 0.587573642, # COMUNS
                                REC_PARLAMENT_VOT_CENS_R == 23 ~ 2.047768089, # VOX 
                                REC_PARLAMENT_VOT_CENS_R == 80 ~ 2.416383432, # ALTRES
                                REC_PARLAMENT_VOT_CENS_R == 96 ~ 1.303544849, # ABST BLANC, NUL
                                TRUE ~ 1)) # PONDERACIÓ BASE

# Perparem variable d'intenció de vot, unim BAN


dataset <- dataset |>
  mutate("INT_PARLAMENT_VOT_R_old" = INT_PARLAMENT_VOT_R,
         "INT_PARLAMENT_VOT_R" = case_when(as.numeric(INT_PARLAMENT_VOT_R) %in% c(93, 94) ~ 96,
                                           TRUE ~ as.numeric(INT_PARLAMENT_VOT_R)))


# Assignem indecisos de manera determinista per simpatia de partit

dataset <- dataset |>
  mutate("int_sim" = INT_PARLAMENT_VOT_R,
         "int_sim" = case_when(((INT_PARLAMENT_VOT_R >= 98) & (as.numeric(SIMPATIA_PARTIT_R) !=95)) ~ as.numeric(SIMPATIA_PARTIT_R),
                               TRUE ~ int_sim))


# Assignem indecisos restants per model mlogit

# Preparem les variables



dataset_num <- dataset  |>
  mutate("intencio_rec" = case_when(INT_PARLAMENT_VOT_R %in% c(80, 93, 94, 95, 96, 97, 98, 99) ~ 93,
                                           TRUE ~ INT_PARLAMENT_VOT_R),
         across(CONEIX_A_FERNANDEZ:VAL_I_GARRIGA, ~case_when(. == 98 ~ as.numeric(NA),
                                                             . == 99 ~ as.numeric(NA),
                                                             TRUE ~ as.numeric(.))),
         "int_sim_rec" = case_when(int_sim %in% c(93, 94, 95, 96, 97, 98, 99) ~ 93,
                                    TRUE ~ int_sim),
         "int_sim_rec2" = case_when(int_sim %in% c(98, 99) ~ 93,
                                   TRUE ~ int_sim),
         across(c(IDEOL_0_10, CAT_0_10, ESP_0_10), ~case_when(. == 98 ~ as.numeric(NA),
                                                              . == 99 ~ as.numeric(NA),
                                                              TRUE ~ as.numeric(.))))
dataset_mlog <- dataset_num %>%
  select(int_sim_rec, VAL_A_FERNANDEZ, VAL_C_PUIGDEMONT, VAL_O_JUNQUERAS, 
         VAL_M_ICETA, VAL_S_ILLA, VAL_J_ALBIACH, VAL_C_CARRIZOSA, 
         VAL_E_REGUANT, VAL_I_GARRIGA, IDEOL_0_10, CAT_0_10, ESP_0_10,
         VAL_GOV_CAT, VAL_GOV_ESP, CLUSTER) %>%
  mutate("int_sim_rec" = as.factor(int_sim_rec))

mldata <- dfidx::dfidx(dataset_mlog, choice="int_sim_rec", shape ="wide", index = "CLUSTER")

model <- mlogit(data = mldata, 
                formula = int_sim_rec~ 0 | VAL_A_FERNANDEZ+VAL_C_PUIGDEMONT+VAL_O_JUNQUERAS+VAL_M_ICETA+VAL_S_ILLA+VAL_J_ALBIACH+VAL_C_CARRIZOSA+VAL_E_REGUANT+VAL_I_GARRIGA+IDEOL_0_10+CAT_0_10+ESP_0_10+VAL_GOV_CAT+VAL_GOV_ESP,
                R = 10000,
                na.action = na.exclude)



# prediccions

preds_aug <- augment(model)

# triar els més probables

preds_aug <- filter(preds_aug, chosen == "TRUE") # NO PREDIU ELS VALORS AMB NA

preds_aug <- filter(preds_aug, .probability > 0.6)

# unir per resultats

jcols <- colnames(select(preds_aug, -c(id, chosen, .probability, .fitted, .resid, alternative)))

dataset_mlog <- dataset_mlog |>
  left_join(select(preds_aug, -c(id, chosen, .probability, .fitted, .resid)), on = jcols)


# substituir 93 quan possible - revisar

dataset_mlog <- dataset_mlog |>
  mutate("est_vote" = case_when(int_sim_rec == 93 ~ alternative,
                                TRUE ~ as.factor(int_sim_rec)))

# només imputa 10 MVs.

# recuperar proporcions

dataset_mlog$pondrvot <- dataset$pondrvot

dataset_mlog <- filter(dataset_mlog, est_vote !=93)
freqs <- wpct(dataset_mlog$est_vote, weight=dataset_mlog$pondrvot)

freqs <- tibble("Partit" = names(freqs),
                "Proporció" = unname(freqs))


freqs <- freqs |>
  mutate("Partit" = case_when(Partit == "1" ~ "PPC",
                              Partit == "3" ~ "ERC",
                              Partit == "4" ~ "PSC",
                              Partit == "6" ~ "C's",
                              Partit == "10" ~ "CUP",
                              Partit == "21" ~ "JxCat",
                              Partit == "22" ~ "CEC-Podem",
                              Partit == "23" ~ "Vox",
                              Partit == "80" ~ "Altres + blanc",
                              Partit == "93" ~ "Nul, Abstenció")) |>
  dplyr::arrange(desc(`Proporció`))

colors <- c("PSC" = "#E73B39", "ERC" = "#FFB232", "JxCat" = "#00C3B2",
            "CEC-Podem" = "#C3113B", "Vox" = "#63BE21", "CUP" = "#ffed00", 
            "PPC" = "#0bb2ff", "C's" = "#EB6109", "Altres + blanc" = "gray")

ggplot(freqs, aes(x=reorder(Partit, Proporció), y=Proporció, fill=Partit))+
  geom_bar(width = 1, stat = "identity") + 
  scale_fill_manual("Partit", values = colors) +
  theme_minimal() +
  theme(axis.text.x=element_blank()) + 
  labs(title = "Estimacions de vot",
       subtitle = "Primera onada Baròmetre 2022",
       caption = "Font: CEO",
       x = "Partit",
       y = "% vot vàlid")
  
