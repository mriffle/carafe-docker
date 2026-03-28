#!/usr/bin/env bash

set -euo pipefail

carafe_version="${CARAFE_VERSION:-2.0.0}"
jar_path="/opt/carafe/carafe-${carafe_version}/carafe-${carafe_version}.jar"

java -Djava.aws.headless=true -jar "${jar_path}" \
    -ms "." \
    -db "AMB1_predictedproteins_contam_QC_eno_Apo.fasta" \
    -i "carafe_input.parquet" \
    -se "DIA-NN" \
    -lf_type diann \
    -device cpu \
    -mode general \
    -fdr 0.01 -ptm_site_prob 0.75 -ptm_site_qvalue 0.01 -itol 20 -itolu ppm -rf -rf_rt_win auto -cor 0.8 -min_mz 200 -n_ion_min 2 -c_ion_min 2 -enzyme 2 -miss_c 1 -fixMod 1 -clip_n_m -minLength 7 -maxLength 35 -min_pep_mz 300 -max_pep_mz 1800 -min_pep_charge 2 -max_pep_charge 4 -lf_frag_mz_min 200 -lf_frag_mz_max 1800 -lf_top_n_frag 20 -lf_min_n_frag 2 -lf_frag_n_min 2 -tf all -nm -nf 4 -min_n 4 -valid -na 0 -ez -fast \
    > >(tee "carafe.stdout") 2> >(tee "carafe.stderr" >&2)
