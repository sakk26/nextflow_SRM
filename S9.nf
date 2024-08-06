nextflow.enable.dsl=2

params.reads = "/home/ec2-user/nf_tut/data/gut_{1,2}.fq"
params.transcriptome = "/home/ec2-user/nf_tut/data/transcriptome.fa"
params.multiqc = "/home/ec2-user/nf_tut/multiqc"
params.outdir = "results"

log.info """\
         R N A S E Q - N F   P I P E L I N E
         ===================================
         transcriptome: ${params.transcriptome}
         reads        : ${params.reads}
         outdir       : ${params.outdir}
         """
         .stripIndent()

/*
 * define the `INDEX` process that create a binary index
 * given the transcriptome file
 */
process INDEX {
    publishDir params.outdir, mode: 'copy'
    input:
    path transcriptome

    output:
    path 'index'

    script:
    """
    salmon index --threads $task.cpus -t $transcriptome -i index
    """
}
Channel
    .fromFilePairs( params.reads, checkIfExists:true )
    .set { read_pairs_ch}

process TRIM_GALORE {
    tag "TrimGalore on $sample_id"
    publishDir "${params.outdir}/trim_galore", mode:'copy'

    input:
    tuple val(sample_id), path(reads)

    output:
    path "*" 
    path "*trimmed*.fq.gz" ,emit :trimmed

    script:
    """
    trim_galore --paired -q 20 --gzip --basename ${sample_id}_trimmed ${reads}
    """
}

/*
 * Run Salmon to perform the quantification of expression using
 * the index and the matched read files
 */
process QUANT {
    tag "quantification on $pair_id"
    publishDir "${params.outdir}/quant", mode:'copy'

    input:
    path index
    tuple val(pair_id), path(reads)

    output:
    path(pair_id)

    script:
    """
    salmon quant --threads $task.cpus --libType=U -i $index -1 ${reads[0]} -2 ${reads[1]} -o $pair_id
    """
}

/*
 * Run fastQC to check quality of reads files
 */
process FASTQC {
    tag "FASTQC on $sample_id"
    publishDir params.outdir, mode: 'copy'
    input:
    tuple val(sample_id), path(reads)

    output:
    path("fastqc_${sample_id}_logs")

    script:
    """
    mkdir fastqc_${sample_id}_logs
    fastqc -o fastqc_${sample_id}_logs -f fastq -q ${reads}
    """
}

/*
 * Create a report using multiQC for the quantification
 * and fastqc processes
 */
process MULTIQC {
    publishDir "${params.outdir}/multiqc", mode:'copy'

    input:
    path('*')

    output:
    path('multiqc_report.html')

    script:
    """
    multiqc .
    """
}

workflow {
    index_ch = INDEX(params.transcriptome)
    trimmed_reads_ch = TRIM_GALORE(read_pairs_ch)
    quant_ch = QUANT(index_ch, read_pairs_ch)
    fastqc_ch = FASTQC(read_pairs_ch)
    MULTIQC(quant_ch.mix(fastqc_ch).collect())
}

workflow.onComplete {
	log.info ( workflow.success ? "\nDone! Open the following report in your browser --> $params.outdir/multiqc/multiqc_report.html\n" : "Oops .. something went wrong" )
}
