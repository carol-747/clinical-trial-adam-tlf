# Statistical Analysis Plan (portfolio exercise)

**Study:** CDISCPILOT01, *Safety and Efficacy of the Xanomeline Transdermal Therapeutic System (TTS) in Patients with Mild to Moderate Alzheimer's Disease*, a randomized, double-blind, placebo-controlled phase II trial.

**Purpose of this document.** This is a practice SAP written for a public demonstration dataset: the CDISC SDTM pilot data distributed in the R package `pharmaversesdtm`. It covers a pre-specified safety analysis and is not the sponsor's SAP. The plan was written before any outcome-level summaries were produced; only the study design, dosing records and the coded adverse event dictionary terms were inspected while writing it.

**Version:** 1.2 · **Author:** Caroline Song (see revision history at the end)

---

## 1. Study design

- Patients randomized 1:1:1 to placebo, xanomeline low dose (54 mg) or xanomeline high dose (81 mg) transdermal patch.
- Planned treatment duration: 24 weeks after baseline.
- Xanomeline is applied to the skin, and application-site and skin reactions are a known safety concern for transdermal systems.

## 2. Objectives

**Primary safety objective.** Compare the time to first dermatologic adverse event between each xanomeline dose and placebo.

**Secondary objectives.**
1. Summarize the incidence of treatment-emergent adverse events (TEAEs) overall and by system organ class (SOC) and preferred term (PT).
2. Describe patient disposition and baseline characteristics.

Efficacy endpoints (ADAS-Cog, CIBIC+) are outside the scope of this plan because the questionnaire domain is not included in the public dataset used here.

## 3. Analysis populations

| Population | Definition | Flag |
|---|---|---|
| Screened | All patients in DM | none |
| Randomized | Randomized (ARM is not "Screen Failure") | `RANDFL` |
| Safety | Randomized and received at least one dose of study treatment (≥ 1 EX record) | `SAFFL = "Y"` |

All safety analyses use the **Safety population**, summarized by **actual treatment** (`TRT01A`).

## 4. Derivations

### 4.1 Treatment dates
- Treatment start date (`TRTSDT`): date of first exposure record with a valid start date.
- Treatment end date (`TRTEDT`): date of last exposure record with a valid end date. If a treated patient has no exposure record with an end date, `TRTEDT` is set to the end-of-study date (`EOSDT`).
- Treatment duration (`TRTDURD`) = `TRTEDT − TRTSDT + 1` days.

### 4.2 Treatment-emergent adverse events
An AE is **treatment-emergent** (`TRTEMFL = "Y"`) if its analysis start date (`ASTDT`) is on or after `TRTSDT` and no later than `TRTEDT + 30` days. AE start dates with a missing day are imputed to the first of the month, and missing day and month to 1 January. An imputed date is never set earlier than `TRTSDT` when the partial date is consistent with on-treatment onset.

### 4.3 Dermatologic adverse events
A **dermatologic AE** is any AE with either:
- a PT beginning with `APPLICATION SITE`, or
- SOC `SKIN AND SUBCUTANEOUS TISSUE DISORDERS`,

excluding the PTs `HYPERHIDROSIS`, `COLD SWEAT` and `ALOPECIA`. These describe sweating or hair loss rather than a skin reaction, and are not plausibly related to patch application.

### 4.4 Time to first dermatologic event (primary endpoint, `ADTTE`, `PARAMCD = "TTDE"`)
- **Origin:** `TRTSDT`.
- **Event:** first dermatologic AE with onset on or after `TRTSDT` and on or before `TRTEDT` (the on-treatment period). `CNSR = 0`.
- **Censoring:** patients without an on-treatment dermatologic AE are censored at `TRTEDT`. `CNSR = 1`.
- **Analysis value:** `AVAL = ADT − STARTDT + 1` (days).
- If several dermatologic AEs start on the same day, the record with the lowest `AESEQ` is used as the source record. This affects traceability only, not `AVAL`.

The on-treatment window (rather than `TRTEDT + 30`) is used for the primary endpoint because patch-related skin reactions are expected to occur during application.

## 5. Statistical methods

### 5.1 General
- Continuous variables: n, mean, SD, median, min and max.
- Categorical variables: n and percentage, with the number of patients in the treatment group as the denominator.
- All tests are two-sided at the 5% level. No adjustment for multiplicity is made. With two dose-versus-placebo comparisons, p-values are descriptive.

### 5.2 Primary endpoint
1. **Kaplan–Meier** estimates of the probability of remaining free of a dermatologic event, by treatment group, with the median time to event and the event-free proportion at weeks 2, 4, 8 and 12.
2. **Log-rank test** comparing the three treatment groups.
3. **Cox proportional hazards model** with treatment group as the only covariate (placebo as reference), reporting hazard ratios with Wald 95% CIs.
4. **Proportional hazards assumption** assessed with scaled Schoenfeld residuals. If it is clearly violated, the hazard ratio is interpreted as an average effect over follow-up and the Kaplan–Meier summaries are emphasized.

### 5.3 Secondary summaries
- **Disposition:** randomized, treated, completed and discontinued, with the primary reason for discontinuation.
- **Demographics and baseline characteristics:** age, age group (< 65, 65–80, > 80 years), sex, race and ethnicity.
- **TEAE overview:** patients with any TEAE, any serious TEAE, any severe TEAE, any TEAE considered possibly or probably related, and any TEAE leading to death.
- **TEAEs by SOC and PT:** number and percentage of patients, counting each patient once per SOC and once per PT, for PTs reported in ≥ 5% of patients in any treatment group.

## 6. Planned tables, listings and figures

| Number | Title | Population |
|---|---|---|
| Table 14.1.1 | Patient disposition | Randomized |
| Table 14.1.2 | Demographic and baseline characteristics | Safety |
| Table 14.3.1 | Overview of treatment-emergent adverse events | Safety |
| Table 14.3.2 | TEAEs by SOC and PT (PT ≥ 5% in any group) | Safety |
| Table 14.3.3 | Time to first dermatologic adverse event | Safety |
| Figure 14.3.1 | Kaplan–Meier plot of time to first dermatologic adverse event | Safety |
| Listing 16.2.1 | Patients who died | Safety |

## 7. Quality control

The primary endpoint dataset (`ADTTE`) and the key numbers in Table 14.3.3 are independently re-derived from SDTM by a second program written in base R without admiral. The two results must match exactly, and any discrepancy is resolved before results are reported.

## 8. Software

R with `admiral` (ADaM derivations), `survival` (time-to-event analysis) and `dplyr`/`knitr` (tables).

## Revision history

| Version | Change | Reason |
|---|---|---|
| 1.0 | Initial plan | — |
| 1.1 | Added the rule for treated patients with no exposure end date (section 4.1) | Two treated patients had no exposure end date; found while reviewing exposure records, before any outcome summaries were produced |
| 1.2 | Added the same-day tie rule for the event source record (section 4.4) | Found while programming ADTTE; changes traceability variables only, not any analysis value |
