# Run the full pipeline: SDTM -> ADaM -> QC -> TLFs
# Usage (from the repository root): Rscript run_all.R

source("R/01_adsl.R")
source("R/02_adae.R")
source("R/03_adtte.R")

# Export ADaM datasets as SAS transport v5 files (FDA submission format)
for (ds in c("adsl", "adae", "adtte")) {
  d <- readRDS(file.path("data/adam", paste0(ds, ".rds")))
  d[] <- lapply(d, function(x) if (is.factor(x)) as.character(x) else x)
  haven::write_xpt(d, file.path("data/adam", paste0(ds, ".xpt")), version = 5, name = toupper(ds))
}

# Independent QC must pass before TLFs are produced
qc_log <- capture.output(source("qc/qc_adtte.R"))
writeLines(qc_log, "qc/qc_log.txt")
cat(qc_log, sep = "\n")

rmarkdown::render("tlf/tlf.Rmd", envir = new.env())
