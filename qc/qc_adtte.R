# Independent QC of ADTTE (PARAMCD = "TTDE") and Table 14.3.3
#
# Double programming: re-derives the primary endpoint directly from SDTM in base R,
# without admiral and without reading any production ADaM dataset, then compares
# the result with the production ADTTE record by record. Spec: sap/SAP.md 3, 4.1-4.4.

library(survival)

dm <- pharmaversesdtm::dm
ds <- pharmaversesdtm::ds
ex <- pharmaversesdtm::ex
ae <- pharmaversesdtm::ae

blank_to_na <- function(x) { x[x == ""] <- NA; x }
ex[] <- lapply(ex, blank_to_na); ae[] <- lapply(ae, blank_to_na); ds[] <- lapply(ds, blank_to_na)

# Safety population and treatment dates (SAP 3, 4.1) -------------------------
valid <- ex$EXDOSE > 0 | (ex$EXDOSE == 0 & grepl("PLACEBO", ex$EXTRT))
ex_v  <- ex[valid, ]
ex_v$st <- as.Date(substr(ex_v$EXSTDTC, 1, 10))
ex_v$en <- as.Date(ifelse(nchar(ex_v$EXENDTC) >= 10, substr(ex_v$EXENDTC, 1, 10), NA))

trtsdt <- tapply(ex_v$st, ex_v$USUBJID, min, na.rm = TRUE)
trtedt <- tapply(ex_v$en, ex_v$USUBJID, function(x) if (all(is.na(x))) NA else max(x, na.rm = TRUE))

saf <- dm[dm$ARM != "Screen Failure" & dm$USUBJID %in% names(trtsdt), c("USUBJID", "ACTARM")]
saf$TRTSDT <- as.Date(trtsdt[saf$USUBJID], origin = "1970-01-01")
saf$TRTEDT <- as.Date(trtedt[saf$USUBJID], origin = "1970-01-01")

# Missing treatment end -> end-of-study disposition date
eos <- ds[ds$DSCAT == "DISPOSITION EVENT", c("USUBJID", "DSSTDTC")]
eos_dt <- setNames(as.Date(eos$DSSTDTC), eos$USUBJID)
miss <- is.na(saf$TRTEDT)
saf$TRTEDT[miss] <- eos_dt[saf$USUBJID[miss]]

# AE start date imputation (SAP 4.2) ----------------------------------------
impute_start <- function(dtc, trtsdt) {
  out <- rep(as.Date(NA), length(dtc))
  full <- !is.na(dtc) & nchar(dtc) >= 10
  ym   <- !is.na(dtc) & nchar(dtc) == 7
  y    <- !is.na(dtc) & nchar(dtc) == 4
  out[full] <- as.Date(substr(dtc[full], 1, 10))
  if (any(ym)) out[ym] <- as.Date(paste0(dtc[ym], "-01"))      # paste0() on an empty vector
  if (any(y))  out[y]  <- as.Date(paste0(dtc[y], "-01-01"))    # would return "-01", so guard
  # Do not impute earlier than first dose when the partial date allows on-treatment onset
  bump_ym <- ym & format(trtsdt, "%Y-%m") == dtc & out < trtsdt
  bump_y  <- y  & format(trtsdt, "%Y") == dtc & out < trtsdt
  out[bump_ym | bump_y] <- trtsdt[bump_ym | bump_y]
  out
}

# Dermatologic definition (SAP 4.3)
derm <- (startsWith(ae$AEDECOD, "APPLICATION SITE") |
           ae$AESOC == "SKIN AND SUBCUTANEOUS TISSUE DISORDERS") &
  !ae$AEDECOD %in% c("HYPERHIDROSIS", "COLD SWEAT", "ALOPECIA")

ae_d <- ae[derm, c("USUBJID", "AESEQ", "AESTDTC")]
ae_d <- merge(ae_d, saf[, c("USUBJID", "TRTSDT", "TRTEDT")], by = "USUBJID")
ae_d$ASTDT <- impute_start(ae_d$AESTDTC, ae_d$TRTSDT)
ae_d <- ae_d[!is.na(ae_d$ASTDT) & ae_d$ASTDT >= ae_d$TRTSDT & ae_d$ASTDT <= ae_d$TRTEDT, ]

first_evt <- tapply(ae_d$ASTDT, ae_d$USUBJID, min)

# Endpoint (SAP 4.4) ----------------------------------------------------------
qc <- saf
qc$EVTDT <- as.Date(first_evt[qc$USUBJID], origin = "1970-01-01")
qc$CNSR  <- ifelse(is.na(qc$EVTDT), 1L, 0L)
qc$ADT   <- as.Date(ifelse(qc$CNSR == 0, qc$EVTDT, qc$TRTEDT), origin = "1970-01-01")
qc$AVAL  <- as.numeric(qc$ADT - qc$TRTSDT) + 1

# Compare with production ---------------------------------------------------
prod <- readRDS("data/adam/adtte.rds")
cmp  <- merge(prod[, c("USUBJID", "ADT", "AVAL", "CNSR")],
              qc[, c("USUBJID", "ADT", "AVAL", "CNSR")],
              by = "USUBJID", suffixes = c("_prod", "_qc"), all = TRUE)

mism <- with(cmp, is.na(AVAL_prod) | is.na(AVAL_qc) |
               ADT_prod != ADT_qc | AVAL_prod != AVAL_qc | CNSR_prod != CNSR_qc)

cat("QC of ADTTE (TTDE)\n")
cat("  Subjects: production", nrow(prod), "| QC", nrow(qc), "\n")
cat("  Mismatched records:", sum(mism), "\n")
if (any(mism)) print(cmp[mism, ])

# Key Table 14.3.3 numbers recomputed independently ------------------------------
arms <- c("Placebo", "Xanomeline Low Dose", "Xanomeline High Dose")
qc$ARM <- factor(qc$ACTARM, arms)
hr_qc <- exp(coef(coxph(Surv(AVAL, 1 - CNSR) ~ ARM, data = qc)))
ev_qc <- tapply(qc$CNSR == 0, qc$ARM, sum)

prod$ARM <- factor(prod$TRT01A, arms)
hr_prod <- exp(coef(coxph(Surv(AVAL, 1 - CNSR) ~ ARM, data = prod)))
ev_prod <- tapply(prod$CNSR == 0, prod$ARM, sum)

cat("  Events by arm (prod / QC):", paste(ev_prod, ev_qc, sep = "/", collapse = ", "), "\n")
cat("  Hazard ratios (prod / QC):", paste(sprintf("%.4f/%.4f", hr_prod, hr_qc), collapse = ", "), "\n")

stopifnot(!any(mism), identical(as.vector(ev_prod), as.vector(ev_qc)),
          isTRUE(all.equal(unname(hr_prod), unname(hr_qc))))
cat("  RESULT: production and QC agree.\n")
