# ADAE: Adverse Events Analysis Dataset
# Source: SDTM AE + ADSL
# Spec: sap/SAP.md sections 4.2 and 4.3

library(admiral)
library(pharmaversesdtm)
library(dplyr)
library(stringr)

ae   <- convert_blanks_to_na(pharmaversesdtm::ae)
adsl <- readRDS("data/adam/adsl.rds")

adsl_vars <- exprs(TRTSDT, TRTEDT, TRT01A, SAFFL, DTHDT)

derm_exclude <- c("HYPERHIDROSIS", "COLD SWEAT", "ALOPECIA")

adae <- ae |>
  derive_vars_merged(dataset_add = adsl, new_vars = adsl_vars,
                     by_vars = exprs(STUDYID, USUBJID)) |>
  # Analysis start date: impute missing day/month to first, never before TRTSDT (SAP 4.2)
  derive_vars_dt(
    dtc = AESTDTC, new_vars_prefix = "AST",
    highest_imputation = "M", date_imputation = "first",
    min_dates = exprs(TRTSDT)
  ) |>
  derive_vars_dt(
    dtc = AEENDTC, new_vars_prefix = "AEN",
    highest_imputation = "M", date_imputation = "last",
    max_dates = exprs(DTHDT)
  ) |>
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ASTDT, AENDT)) |>
  # Treatment-emergent flag: onset from first dose to last dose + 30 days (SAP 4.2)
  derive_var_trtemfl(
    start_date = ASTDT, end_date = AENDT,
    trt_start_date = TRTSDT, trt_end_date = TRTEDT,
    end_window = 30
  ) |>
  # Dermatologic event flag (SAP 4.3)
  mutate(
    CQ01NAM = if_else(
      (str_starts(AEDECOD, "APPLICATION SITE") |
         AESOC == "SKIN AND SUBCUTANEOUS TISSUE DISORDERS") &
        !AEDECOD %in% derm_exclude,
      "DERMATOLOGIC EVENTS", NA_character_
    ),
    # On-treatment window used for the primary endpoint (SAP 4.4)
    ONTRTFL = if_else(!is.na(ASTDT) & ASTDT >= TRTSDT & ASTDT <= TRTEDT, "Y", NA_character_)
  )

saveRDS(adae, "data/adam/adae.rds")
message("ADAE: ", nrow(adae), " records; TEAEs ", sum(adae$TRTEMFL == "Y", na.rm = TRUE),
        "; dermatologic ", sum(!is.na(adae$CQ01NAM)))
