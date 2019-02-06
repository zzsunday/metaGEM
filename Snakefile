configfile: "config.yaml"

import os
import glob

R1 = sorted([os.path.splitext(val)[0] for val in (glob.glob('/c3se/NOBACKUP/groups/c3-c3se605-17-8/projects_francisco/binning/perSamplePipe/concoct_output/ERR*'))]) #These commands dont recognize the config.yaml file so had to hardcode raw data filepath

names = [os.path.basename(val) for val in R1]

#namesR1 = [os.path.basename(val) for val in R1]
#names = [x[:-2] for x in namesR1]

rule all:
    input:
        expand("bracken_out/{names}/output.bracken", names = names)
    output:
        "pipemap.png"
    shell:
        """
        snakemake --dag | dot -Tpng > {output}
        """

#rule megahit:
#    input:
#        R1=config["paths"]["raw_reads"]+"/{ref}_1.fastq",
#        R2=config["paths"]["raw_reads"]+"/{ref}_2.fastq"
#    output:
#        "megahitAssembly/{ref}/final.contigs.fa"
#    shell:
#        """
#        rm -r $(dirname {output})
#        megahit -t {config[megahit_params][threads]} --tmp-dir $TMPDIR --presets meta-large --verbose -1 {input.R1} -2 {input.R2} --continue -o {config[paths][concoct_run]}/$(dirname {output})
#        """

#rule cutcontigs:
#    input:
#        "megahitAssembly/{ref}/final.contigs.fa"
#    output:
#        "contigs/{ref}/megahit_c10K.fa"
#    shell:
#        """
#        set +u;source activate concoct_env;set -u;
#        cd $(dirname {input})
#        python {config[cutcontigs_params][script_dir]} -c 10000 -o 0 -m $(basename {input}) > $(basename {output});
#        mv $(basename {output}) {config[paths][concoct_run]}/$(dirname {output});
#        cd {config[paths][concoct_run]}
#        tar -cvf {output} megahitAssembly/
#        """

#rule kallistoBuild:
#    input:
#        "contigs/{ref}/megahit_c10K.fa"
#    output:
#        "quantification/kallistoIndices/{ref}.kaix"
#    shell:
#        """
#        set +u;source activate checkm_env;set -u;
#        kallisto index {input} -i {output}
#        """

#rule gatherIndexes:
#    input:
#        expand("quantification/kallistoIndices/{ref}.kaix", ref = names)
#    output:
#        "quantification/kallistoIndices/indexDummy.txt"
#    shell:
#        """
#        touch {output}
#        """

#rule kallistoQuant:
#    input:
#        R1= config["paths"]["raw_reads"]+"/{names}_1.fastq",
#        R2= config["paths"]["raw_reads"]+"/{names}_2.fastq",
#        index="quantification/kallistoIndices/{ref}.kaix",
#        indexDummy="quantification/kallistoIndices/indexDummy.txt"
#    output:
#        "quantification/ref_{ref}/{names}/abundance.tsv.gz"
#    threads: 16
#    shell:
#        """
#        set +u;source activate checkm_env;set -u;
#        cd $TMPDIR
#        kallisto quant --threads {config[kallisto_params][threads]} --plaintext -i {config[paths][concoct_run]}/{input.index} -o $TMPDIR {input.R1} {input.R2}
#        gzip abundance.tsv
#        cp $(basename {output}) {config[paths][concoct_run]}/$(dirname {output})
#        cp run_info.json {config[paths][concoct_run]}/$(dirname {output})
#        rm $(basename {output})
#        rm run_info.json
#        cd {config[paths][concoct_run]}
#        """

#rule gatherAbundance:
#    input:
#        expand("quantification/ref_{ref}/{names}/abundance.tsv.gz",ref=names, names=names)
#    output:
#        "quantification/quantDummy.txt"
#    shell:
#        """
#        touch {output}
#        """

rule kallisto2concoctTable:
    input:
        abundances = lambda wildcards: expand("quantification/ref_{ref}/{{names}}/abundance.tsv.gz".format(ref=wildcards.concoct), names = names),
        abdunaceDummy= "quantification/quantDummy.txt"
    output:
        "concoct_input/{concoct}_concoct_inputtableR.tsv"
    params:
        files= names
    shell:
        """
        set +u;source activate concoct_env;set -u;
        python {config[kallisto_params][script]} \
            --samplenames <(for s in {params.files}; do echo $s; done) \
                {input.abundances} > {output}
        """

rule concoct:
    input:
        table="concoct_input/{names}_concoct_inputtableR.tsv",
        comp="contigs/{names}/megahit_c10K.fa"
    output:
        "concoct_output/{names}/clustering_gt1000.csv"
    shell:
        """
        set +u;source activate concoct_env;set -u;
        cd {config[paths][concoct_run]};
        concoct --coverage_file {input.table} --composition_file {input.comp} -b $(dirname {output}) -t {config[concoct_params][threads]} -c {config[concoct_params][clusters]}
        cut -d"," -f2 $(dirname {output})/clustering_gt1000.csv | sort | uniq -c | wc > $(dirname {output})/binfo.txt
        """

rule mergeClustering:
    input:
        "concoct_output/{names}/clustering_gt1000.csv"
    output:
        "concoct_output/{names}/clustering_merged.csv"
    shell:
        """
        set +u;source activate concoct_env;set -u;
        merge_cutup_clustering.py {input} > {output}
        """

rule extractBins:
    input:
        clustering="concoct_output/{names}/clustering_merged.csv",
        OGcontigs="megahitAssembly/{names}.final.contigs.fa"
    output:
        "bins/{names}"
    shell:
        """
        set +u;source activate concoct_env;set -u;
        mkdir -p {output}
        extract_fasta_bins.py {input.OGcontigs} {input.clustering} --output_path {output}
        """

rule checkM:
    input:
        "bins/{names}"
    output:
        "checkm_out/{names}/lineage.ms"
    shell:
        """
        set +u;source activate checkm_env;set -u;
        checkm lineage_wf --tmpdir $TMPDIR -x fa -t {config[checkM_params][threads]} --pplacer_threads {config[checkM_params][threads]} {input} $(dirname {output})
        """

rule checkMtable:
    input:
        "checkm_out/{names}/lineage.ms"
    output:
        "checkm_out/{names}/binTable.txt"
    shell:
        """
        set +u;source activate checkm_env;set -u;
        checkm qa --tmpdir $TMPDIR --tab_table $(dirname {output})/lineage.ms $(dirname {output}) > {output}
        """

rule binFilter:
    input:
        bins= "bins/{names}",
        table= "checkm_out/{names}/binTable.txt"
    output:
        "bins_filtered/{names}"
    shell:
        """
        mkdir -p {output}
        {config[checkM_params][filterScript]} {input.bins} {input.table} {output} --min_completeness {config[checkM_params][comp]} --max_contamination {config[checkM_params][cont]}
        """

rule zipBins:
    input:
        expand("bins_filtered/{names}", names=names)
    output:
        "bins.gz"
    shell:
        """
        gzip bins
        """

rule kraken2:
    input:
        binsFilt="bins_filtered/{names}",
        binZip="bins.gz"
    output:
        classified="kraken2_out/{names}/classified",
        unclassified="kraken2_out/{names}/unclassified",
        report="kraken2_out/{names}/report.txt"
    shell:
        """
        set +u;source activate checkm_env;set -u;
        kraken2 --db {config[kraken2_params][db]} --threads {config[kraken2_params][threads]} --unclassified-out {output.unclassified} --classified-out {output.classified} --report {output.report} --use-names {input.binsFilt}/*
        """

rule bracken:
    input:
        report="kraken2_out/{names}/report.txt"
    output:
        "bracken_out/{names}/output.bracken"
    shell:
        """
        set +u;source activate checkm_env;set -u;
        bracken -d {config[kraken2_params][db]} -i {input.report} -o {output}
        """

#rule carveme:
#    input:
#        "bins_filtered/{names}/{fasta}"
#    output:
#        "carvemeOut/{names}/{fasta}.xml"
#    shell:
#        """
#        set +u;source activate concoct_env;set -u
#        carve --dna {input} -o {output}
#        """
#rule memote:
#    input: "carvemeOut/{speciesProt}.xml"
#    output: "carvemeOut/{speciesProt}.xml.html"
#    shell:
#        """
#        set +u;source activate concoct_env;set -u
#        memote report snapshot --filename "{input}.html" {input} #generate .html report
#        memote run {input} #generate quick printout of model summary
#        """

#ADD SMETANA RULE


                            #BELOW ARE RULES USEFUL FOR EXTRACTING BINS USING MY OWN R SCRIPT, NO LONGER USED

#rule parseFASTA:
#    input:"evaluation-output/clustering_gt1000_scg.tab"
#    output: "speciesProt"#dynamic("carvemeOut/{speciesProt}.txt"),dynamic("speciesDNA/{speciesDNA}.txt")
#    shell:
#        """
#        cd {config[paths][concoct_run]}
#        mkdir -p {config[speciesProt_params][dir]}
#        cp {input} {config[paths][concoct_run]}/{config[speciesProt_params][dir]}
#        cd {config[speciesProt_params][dir]}
#        sed -i '1d' {config[speciesProt_params][infile]} #removes first row
#        awk '{{print $2}}' {config[speciesProt_params][infile]} > allspecies.txt #extracts node information
#        sed '/^>/ s/ .*//' {config[speciesDNA_params][FASTA]} > {config[speciesDNA_params][FASTAcleanID]} #removes annotation to gene ID
#        sed '/^>/ s/ .*//' {config[speciesProt_params][pFASTA]} > {config[speciesProt_params][pFASTAcleanID]} #removes annotation to protein ID
#        Rscript {config[speciesProt_params][scriptdir]}multiFASTA2speciesFASTA.R
#        sed -i 's/"//g' species*
#        sed -i '/k99/s/^/>/' species*
#        sed -i 's/{config[speciesProt_params][tab]}/{config[speciesProt_params][newline]}/' species*
#        sed -i '1d' speciesDNA* #remove first row
#        sed -i '1d' speciesDNA* #remove second row
#        cd {config[paths][concoct_run]}
#        """

#rule pseudoProt:
#    input: "speciesProt"
#    output: dynamic("carvemeOut/{speciesProt}.txt")
#    shell:
#        """
#        cd {config[paths][concoct_run]}
#        mkdir -p {config[carveme_params][dir]}
#        cd {config[carveme_params][dir]}
#        cp {config[paths][concoct_run]}/{config[speciesProt_params][dir]}/speciesProt*.txt {config[paths][concoct_run]}/{config[carveme_params][dir]}
#        find . -name "species*.txt" -size -{config[carveme_params][cutoff]} -delete #delete files with little information, these cause trouble
#        cd {config[paths][concoct_run]}
#        """

#rule pseudoDNA:
#    input: "speciesProt"
#    output: dynamic("speciesDNA/{speciesDNA}.fa")
#    shell:
#        """
#        cd {config[paths][concoct_run]}
#        mkdir -p {config[speciesDNA_params][dir]}
#        cp {config[speciesProt_params][dir]}/speciesDNA*.txt {config[paths][concoct_run]}/{config[speciesDNA_params][dir]}
#        cp {config[speciesProt_params][dir]}/cleanID.fa {config[paths][concoct_run]}/{config[speciesDNA_params][dir]}
#        cd {config[speciesDNA_params][dir]}
#        find . -name "species*.txt" -size -{config[speciesDNA_params][cutoff]} -delete #delete files with little information, these cause trouble
#        for file in *.txt; do
#            mv "$file" "$(basename "$file" .txt).fa"
#        done
#        cd {config[paths][concoct_run]}
#        """

#rule requiredRule:
#    input: dynamic("speciesDNA/{speciesDNA}.txt")
#    output: "requiredDummyFile"
#    shell: "cd {config[paths][concoct_run]} ;touch {output}"



                ##BELOW ARE THE RULES FOR GENERATING BOWTIE INDEX, BOWTIE ALLIGNMENT, AND COVTABLE

#rule bowtieBuild:
#    input:"contigs/{names}/megahit_c10K.fa"
#    output:"contigs/{names}/buildDummy.txt"
#    shell:
#        """
#        set +u;source activate concoct_env;set -u;
#        cd $(dirname {input});
#        bowtie2-build $(basename {input}) $(basename {input});
#        cd {config[paths][concoct_run]};
#        touch {output}
#        """

#rule bowtie:
#    input:
#        assembly="contigs/{names}/megahit_c10K.fa",
#        reads=config["paths"]["raw_reads"]+"/{names}_1.fastq",
#        index= "contigs/{names}/buildDummy.txt"
#    output:"map/{names}"
#    shell:
#        """
#        set +u;source activate concoct_env;set -u;
#        export MRKDUP={config[bowtie_params][MRKDUP_jardir]};
#        DIRECTORY={output}
#        if [ ! -d "$DIRECTORY" ]; then
#            mkdir -p {output}
#            cd {output};
#            bash {config[bowtie_params][MRKDUP_shelldir]} -c -t {config[bowtie_params][threads]} -p '-q' {input.reads} $(echo {input.reads} | sed s/_1.fastq/_2.fastq/) pair {config[paths][concoct_run]}/{input.assembly} asm bowtie2;
#            cd {config[paths][concoct_run]};
#        fi
#        """
#rule covtable:
#    input: "map/{names}"
#    output:"concoct-input/{names}/concoct_inputtable.tsv"
#    shell:
#        """
#        set +u;source activate concoct_env;set -u;
#        cd {config[paths][concoct_run]}/{input}
#        python {config[paths][CONCOCT]}/scripts/gen_input_table.py --isbedfiles \
#            --samplenames <(for s in ERR*; do echo $s | cut -d'_' -f1; done) \
#            ../contigs/{names}/megahit_c10K.fa */bowtie2/asm_pair-smds.coverage > concoct_inputtable.tsv;
#        mkdir -p {config[paths][concoct_run]}/concoct_input/{names};
#        mv concoct_inputtable.tsv {config[paths][concoct_run]}/concoct_input/{names};
#        """
