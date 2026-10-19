# ADTTE: Time-to-Event Analysis Dataset
# PARAMCD = "TTDE": time to first dermatologic adverse event
# Source: ADSL, ADAE
# Spec: sap/SAP.md section 4.4

library(admiral)
library(dplyr)

adsl <- readRDS("data/adam/adsl.rds") |> filter(SAFFL == "Y")
adae <- readRDS("data/adam/adae.rds")

# Event: first on-treatment dermatologic AE
derm_event <- event_source(
  dataset_name = "adae",
  filter = CQ01NAM == "DERMATOLOGIC EVENTS" & ONTRTFL == "Y",
  date = ASTDT,
  order = exprs(AESEQ),  # ties on the same day: lowest AESEQ
  set_values_to = exprs(
    EVNTDESC = "FIRST DERMATOLOGIC ADVERSE EVENT",
    SRCDOM = "ADAE", SRCVAR = "ASTDT", SRCSEQ = AESEQ
  )
)

# Censoring: end of treatment
end_of_treatment <- censor_source(
  dataset_name = "adsl",
  date = TRTEDT,
  set_values_to = exprs(
    EVNTDESC = "END OF TREATMENT",
    SRCDOM = "ADSL", SRCVAR = "TRTEDT"
  )
)

adtte <- derive_param_tte(
  dataset_adsl = adsl,
  start_date = TRTSDT,
  event_conditions = list(derm_event),
  censor_conditions = list(end_of_treatment),
  source_datasets = list(adsl = adsl, adae = adae),
  set_values_to = exprs(
    PARAMCD = "TTDE",
    PARAM = "Time to First Dermatologic Adverse Event (days)"
  )
) |>
  derive_vars_duration(new_var = AVAL, start_date = STARTDT, end_date = ADT) |>
  derive_vars_merged(dataset_add = adsl, new_vars = exprs(TRT01A, AGE, SEX),
                     by_vars = exprs(STUDYID, USUBJID))

saveRDS(adtte, "data/adam/adtte.rds")
message("ADTTE: ", nrow(adtte), " subjects; events ", sum(adtte$CNSR == 0))
