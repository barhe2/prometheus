@NonCPS
def getChangedFilesList() {
    def changedFiles = []
    for (changeLogSet in currentBuild.changeSets) {
        for (entry in changeLogSet.getItems()) {
            for (file in entry.getAffectedFiles()) {
                changedFiles.add(file.getPath())
            }
        }
    }
    return changedFiles
}

pipeline {
    agent any

    environment {
        TERRAFORM_DIR = 'terraform'
        ANSIBLE_DIR = 'ansible'
        MANIFEST_FILE = 'manifest.json'
        MANIFEST_CHANGED = false
        CLUSTER_NAME = ''
        CONTROL_PLANE_TYPE = ''
        CONTROL_PLANE_COUNT = ''
        WORKER_NODE_TYPE = ''
        WORKER_NODE_COUNT = ''
        CONTROL_PLANE_IP = ''
    }

    stages {
        stage('Check Changed Files') {
            steps {
                script {
                    def changedFiles = getChangedFilesList()
                    echo "Changed Files: ${changedFiles}"

                    def manifestChanged = changedFiles.any { it.contains(env.MANIFEST_FILE) }
                    env.MANIFEST_CHANGED = manifestChanged
                    if (env.MANIFEST_CHANGED) {
                        echo "✅ ${env.MANIFEST_FILE} was changed - proceeding with cluster provisioning"
                    } else {
                        echo "⚠️ No changes to ${env.MANIFEST_FILE} detected"
                    }
                }
            }
        }

        stage('Parse Manifest') {
            when {
                expression { return env.MANIFEST_CHANGED }
            }
            steps {
                script {
                    if (!fileExists(env.MANIFEST_FILE)) {
                        error "Manifest file '${env.MANIFEST_FILE}' not found!"
                    }

                    // --- ADDED DEBUGGING STEPS ---
                    echo "Contents of ${env.MANIFEST_FILE}:"
                    sh "cat ${env.MANIFEST_FILE}" // Print the actual content Jenkins sees
                    echo "Attempting to parse JSON..."
                    // --- END DEBUGGING STEPS ---

                    def manifest = readJSON file: env.MANIFEST_FILE

                    // --- ADDED DEBUGGING STEPS ---
                    echo "Parsed manifest object keys: ${manifest.keySet()}"
                    echo "Parsed manifest control_plane: ${manifest.control_plane}"
                    echo "Parsed manifest worker_nodes: ${manifest.worker_nodes}"
                    // --- END DEBUGGING STEPS ---

                    env.CLUSTER_NAME = manifest.cluster_name
                    env.CONTROL_PLANE_TYPE = manifest.control_plane.instance_type
                    env.CONTROL_PLANE_COUNT = manifest.control_plane.count
                    env.WORKER_NODE_TYPE = manifest.worker_nodes.instance_type
                    env.WORKER_NODE_COUNT = manifest.worker_nodes.count

                    echo "==== Cluster Configuration ===="
                    echo "Cluster Name: ${env.CLUSTER_NAME}"
                    echo "Control Plane: ${env.CONTROL_PLANE_COUNT}x ${env.CONTROL_PLANE_TYPE}"
                    echo "Worker Nodes: ${env.WORKER_NODE_COUNT}x ${env.WORKER_NODE_TYPE}"
                }
            }
        }

        stage('Prepare Terraform') {
            when {
                expression { return env.MANIFEST_CHANGED }
            }
            steps {
                script {
                    sh "mkdir -p ${env.TERRAFORM_DIR}"
                    writeFile file: "${env.TERRAFORM_DIR}/terraform.tfvars", text: """
                        cluster_name = "${env.CLUSTER_NAME}"
                        control_plane_instance_type = "${env.CONTROL_PLANE_TYPE}"
                        control_plane_count = ${env.CONTROL_PLANE_COUNT}
                        worker_instance_type = "${env.WORKER_NODE_TYPE}"
                        worker_count = ${env.WORKER_NODE_COUNT}
                        region = "us-west-2"
                        key_name = "Moni"
                    """
                }
            }
        }

        stage('Terraform Init & Apply') {
            when {
                expression { return env.MANIFEST_CHANGED }
            }
            steps {
                dir(env.TERRAFORM_DIR) {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                        credentialsId: 'aws-credentials',
                                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                        sh 'terraform init'
                        sh 'terraform apply -auto-approve'
                        sh 'cp terraform.tfstate ../'
                    }
                }
            }
        }

        stage('Generate Ansible Inventory') {
            when {
                expression { return env.MANIFEST_CHANGED }
            }
            steps {
                script {
                    sh 'pwd'
                    sh "mkdir -p ${env.ANSIBLE_DIR}"
                    def terraformState = readJSON file: 'terraform.tfstate'
                    def controlPlanePublicIp = terraformState.outputs.control_plane_public_ip.value
                    env.CONTROL_PLANE_IP = controlPlanePublicIp

                    def workerIpsMap = [:]
                    terraformState.outputs.worker_public_ips.value.each { key, value ->
                        workerIpsMap[key] = value
                    }

                    writeFile file: "${env.ANSIBLE_DIR}/inventory.yaml", text: """
all:
  vars:
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
    ansible_user: ubuntu
    ansible_python_interpreter: /usr/bin/python3
  children:
    controls:
      hosts:
        control_plane:
          ansible_host: ${controlPlanePublicIp}
    workers:
      hosts:
${workerIpsMap.collect { key, value -> "        ${key}:\n          ansible_host: ${value}" }.join('\n')}
                    """
                    echo "Ansible inventory generated:"
                    echo readFile("${env.ANSIBLE_DIR}/inventory.yaml")
                }
            }
        }

        stage('Run Ansible Playbook') {
            when {
                expression { return env.MANIFEST_CHANGED }
            }
            steps {
                script {
                    echo "==== Contents of Ansible Inventory ===="
                    sh "cat ${env.ANSIBLE_DIR}/inventory.yaml"

                    sshagent(['ssh-credentials']) {
                        sh """
                            set -e
                            ansible-playbook -i ${env.ANSIBLE_DIR}/inventory.yaml ${env.ANSIBLE_DIR}/main.yaml --ssh-extra-args='-o StrictHostKeyChecking=no'
                        """
                    }
                }
            }
        }

        stage('Retrieve and Modify Kubeconfig') {
            when {
                expression { return env.MANIFEST_CHANGED }
            }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'ssh-credentials', keyFileVariable: 'SSH_KEY')]) {
                    sh """
                        set -e
                        scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no ubuntu@${env.CONTROL_PLANE_IP}:/home/ubuntu/.kube/config kubeconfig
                        sed -i 's|server: https://.*:6443|server: https://${env.CONTROL_PLANE_IP}:6443|' kubeconfig
                    """
                }
            }
        }

        stage('Push Files to Git Repository') {
            when {
                expression { return env.MANIFEST_CHANGED }
            }
            steps {
                script {
                    echo "Skipping Git push as this stage is not fully implemented yet."
                }
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline completed successfully!"
            script {
                if (!env.MANIFEST_CHANGED) {
                    echo "No manifest changes detected - no cluster provisioning needed."
                }
            }
        }
        failure {
            echo "❌ Pipeline failed!"
        }
        always {
            sh 'rm -f ~/.ssh/id_rsa || true'
            sh 'rm -f kubeconfig || true'
        }
    }
}