# ADSL: Subject-Level Analysis Dataset
# Source: SDTM DM, DS, EX, AE (pharmaversesdtm, CDISCPILOT01)
# Spec: sap/SAP.md sections 3 and 4.1

library(admiral)
library(pharmaversesdtm)
library(dplyr)
library(stringr)

dm <- convert_blanks_to_na(pharmaversesdtm::dm)
ds <- convert_blanks_to_na(pharmaversesdtm::ds)
ex <- convert_blanks_to_na(pharmaversesdtm::ex)
ae <- convert_blanks_to_na(pharmaversesdtm::ae)

# Exposure dates ----------------------------------------------------------
ex_ext <- ex |>
  derive_vars_dt(dtc = EXSTDTC, new_vars_prefix = "EXST") |>
  derive_vars_dt(dtc = EXENDTC, new_vars_prefix = "EXEN")

valid_dose <- expr(EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO")))

# Disposition dates -------------------------------------------------------
ds_ext <- derive_vars_dt(ds, dtc = DSSTDTC, new_vars_prefix = "DSST")

format_eosstt <- function(x) {
  case_when(
    x == "COMPLETED"      ~ "COMPLETED",
    x == "SCREEN FAILURE" ~ NA_character_,
    !is.na(x)             ~ "DISCONTINUED",
    TRUE                  ~ "ONGOING"
  )
}

# ADSL ----------------------------------------------------------------------
adsl <- dm |>
  select(-DOMAIN) |>
  mutate(TRT01P = ARM, TRT01A = ACTARM) |>
  # Treatment start and end dates (SAP 4.1)
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add  = !!valid_dose & !is.na(EXSTDT),
    new_vars    = exprs(TRTSDT = EXSTDT),
    order       = exprs(EXSTDT, EXSEQ),
    mode        = "first",
    by_vars     = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add  = !!valid_dose & !is.na(EXENDT),
    new_vars    = exprs(TRTEDT = EXENDT),
    order       = exprs(EXENDT, EXSEQ),
    mode        = "last",
    by_vars     = exprs(STUDYID, USUBJID)
  ) |>
  # End-of-study status and reason
  derive_vars_merged(
    dataset_add = ds_ext,
    by_vars     = exprs(STUDYID, USUBJID),
    filter_add  = DSCAT == "DISPOSITION EVENT",
    new_vars    = exprs(EOSDT = DSSTDT, EOSSTT = format_eosstt(DSDECOD), DCSREAS = DSDECOD),
    missing_values = exprs(EOSSTT = "ONGOING")
  ) |>
  mutate(DCSREAS = if_else(EOSSTT == "DISCONTINUED", DCSREAS, NA_character_)) |>
  # SAP 4.1: if no exposure record has an end date, treatment end = end-of-study date
  mutate(TRTEDT = coalesce(TRTEDT, if_else(!is.na(TRTSDT), EOSDT, as.Date(NA)))) |>
  derive_var_trtdurd() |>
  # Randomization date
  derive_vars_merged(
    dataset_add = ds_ext,
    by_vars     = exprs(STUDYID, USUBJID),
    filter_add  = DSDECOD == "RANDOMIZED",
    new_vars    = exprs(RANDDT = DSSTDT)
  ) |>
  # Death date (partial dates imputed to first day/month)
  derive_vars_dt(
    new_vars_prefix = "DTH", dtc = DTHDTC,
    highest_imputation = "M", date_imputation = "first"
  ) |>
  # Population flags (SAP 3)
  mutate(RANDFL = if_else(ARM != "Screen Failure", "Y", "N")) |>
  derive_var_merged_exist_flag(
    dataset_add = ex,
    by_vars     = exprs(STUDYID, USUBJID),
    new_var     = SAFFL,
    false_value = "N",
    missing_value = "N",
    condition   = !!valid_dose
  ) |>
  mutate(SAFFL = if_else(RANDFL == "Y", SAFFL, "N")) |>
  # Grouping variables (SAP 5.3)
  mutate(
    AGEGR1 = case_when(AGE < 65 ~ "<65", AGE <= 80 ~ "65-80", AGE > 80 ~ ">80"),
    AGEGR1 = factor(AGEGR1, c("<65", "65-80", ">80")),
    TRT01A = factor(TRT01A, c("Placebo", "Xanomeline Low Dose", "Xanomeline High Dose")),
    TRT01P = factor(TRT01P, c("Placebo", "Xanomeline Low Dose", "Xanomeline High Dose"))
  )

dir.create("data/adam", recursive = TRUE, showWarnings = FALSE)
saveRDS(adsl, "data/adam/adsl.rds")
message("ADSL: ", nrow(adsl), " subjects; safety population ", sum(adsl$SAFFL == "Y"))
