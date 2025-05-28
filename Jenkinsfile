// Returns a list of changed files
@NonCPS
def getChangedFilesList() {
    def changedFiles = []
    for (changeLogSet in currentBuild.changeSets) {
        for (entry in changeLogSet.getItems()) { // For each commit in the detected changes
            for (file in entry.getAffectedFiles()) {
                changedFiles.add(file.getPath()) // Add changed file to list
            }
        }
    }
    return changedFiles
}

pipeline {
    agent any

    environment {
        TERRAFORM_DIR = 'terraform' // Directory where Terraform files are located
        ANSIBLE_DIR = 'ansible' // Directory where Ansible files are located
        MANIFEST_FILE = 'manifest.json'
        MANIFEST_CHANGED = false
    }

    stages {
        stage('Check Changed Files') {
            steps {
                script {
                    def changedFiles = getChangedFilesList()
                    echo "Changed Files: ${changedFiles}"

                    // Check if manifest.json was changed
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
                    def manifest = readJSON file: env.MANIFEST_FILE
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
                    writeFile file: "${env.TERRAFORM_DIR}/terraform.tfvars", text: """
                        cluster_name = "${env.CLUSTER_NAME}"
                        control_plane_instance_type = "${env.CONTROL_PLANE_TYPE}"
                        control_plane_count = ${env.CONTROL_PLANE_COUNT}
                        worker_instance_type = "${env.WORKER_NODE_TYPE}"
                        worker_count = ${env.WORKER_NODE_COUNT}
                        region = "us-west-2"
                        key_name = "Moni" # 👈 ודא שזה שם מפתח ה-AWS הנכון שלך
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
                sh 'terraform output'
                sh 'terraform state push terraform.tfstate' // 👈 הוספנו את שם הקובץ
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
            def workerIpsMap = [:]
            for (def key in terraformState.outputs.worker_public_ips.value.keySet()) {
                workerIpsMap[key] = terraformState.outputs.worker_public_ips.value[key]
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
                    ansible-playbook -i ${env.ANSIBLE_DIR}/inventory.yaml ansible/main.yaml --ssh-extra-args='-o StrictHostKeyChecking=no'
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
                        scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ubuntu@${env.CONTROL_PLANE_IP}:/home/ubuntu/.kube/config kubeconfig
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
                    sh "mkdir -p enviormentSetup"
                    sh """
                        set -e
                        cp ${env.TERRAFORM_DIR}/terraform.tfstate enviormentSetup/
                        cp kubeconfig enviormentSetup/
                    """
                    sshagent(['github-credentials']) {
                        sh """
                            set -e
                            git config --global user.email "jenkins@example.com"
                            git config --global user.name "Jenkins"
                            git add enviormentSetup/terraform.tfstate enviormentSetup/kubeconfig
                            git commit -m "Add kubeconfig and terraform state for ${env.CLUSTER_NAME}"
                            git push origin HEAD:main
                        """
                    }
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
