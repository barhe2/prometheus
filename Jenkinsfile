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
        MANIFEST_CHANGED = false // This will be set by the script step
        CLUSTER_NAME = '' // Initialize for clarity
        CONTROL_PLANE_TYPE = '' // Initialize
        CONTROL_PLANE_COUNT = '' // Initialize
        WORKER_NODE_TYPE = '' // Initialize
        WORKER_NODE_COUNT = '' // Initialize
        CONTROL_PLANE_IP = '' // Crucial: Initialize this as it's used later
    }

    stages {
        stage('Check Changed Files') {
            steps {
                script {
                    def changedFiles = getChangedFilesList()
                    echo "Changed Files: ${changedFiles}"

                    // Check if manifest.json was changed
                    // Using `contains` is generally okay, but `endsWith` might be more precise for a file name.
                    // However, given it's `manifest.json`, `contains` should work fine.
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
                    // Ensure the TERRAFORM_DIR exists before writing the file into it
                    sh "mkdir -p ${env.TERRAFORM_DIR}"
                    writeFile file: "${env.TERRAFORM_DIR}/terraform.tfvars", text: """
                        cluster_name = "${env.CLUSTER_NAME}"
                        control_plane_instance_type = "${env.CONTROL_PLANE_TYPE}"
                        control_plane_count = ${env.CONTROL_PLANE_COUNT}
                        worker_instance_type = "${env.WORKER_NODE_TYPE}"
                        worker_count = ${env.WORKER_NODE_COUNT}
                        region = "us-west-2" // 👈 Consider making this dynamic (e.g., pipeline parameter or env var)
                        key_name = "Moni"   // 👈 Ensure this is your correct AWS key pair name, consider making it dynamic
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
                                        credentialsId: 'aws-credentials', // Ensure this ID matches your Jenkins AWS credentials
                                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY']]) {
                        sh 'terraform init'
                        sh 'terraform apply -auto-approve'
                        // Terraform output is usually for display or to pass values,
                        // if you need a specific output, use `readStdout` or similar.
                        // sh 'terraform output' // Removed as it's not captured here

                        // Ensure terraform state is pushed to S3/remote backend if configured
                        // `terraform state push` is usually for pushing local state to a remote backend.
                        // If you use a remote backend configured in your .tf files,
                        // `terraform apply` usually handles state updates automatically.
                        // If not, and you want to push to a *local* state file that might be
                        // picked up later, then `terraform state push terraform.tfstate` is correct.
                        // However, a best practice for production is a remote backend (S3, Atlas, etc.).
                        // sh 'terraform state push terraform.tfstate' // Keep if you explicitly need it this way

                        // The `cp terraform.tfstate ../` is crucial for the next stage to read it.
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
                    // Ensure terraform.tfstate is accessible. It was copied to `../` in the previous stage.
                    def terraformState = readJSON file: 'terraform.tfstate'
                    def controlPlanePublicIp = terraformState.outputs.control_plane_public_ip.value
                    // FIX: Set env.CONTROL_PLANE_IP for the next stage
                    env.CONTROL_PLANE_IP = controlPlanePublicIp

                    def workerIpsMap = [:]
                    // Iterate correctly over the map entries from Terraform output
                    // Assuming worker_public_ips.value is a map (JSON object)
                    terraformState.outputs.worker_public_ips.value.each { key, value ->
                        workerIpsMap[key] = value
                    }

                    writeFile file: "${env.ANSIBLE_DIR}/inventory.yaml", text: """
all:
  vars:
    ansible_ssh_private_key_file: ~/.ssh/id_rsa // This needs to be set up by sshagent
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

                    // 'ssh-credentials' should be a "SSH Username with private key" credential in Jenkins
                    sshagent(['ssh-credentials']) { // Ensure this ID matches your Jenkins SSH credentials
                        sh """
                            set -e
                            # The private key will be made available by sshagent in a temporary file.
                            # Ansible will use this file for authentication.
                            # No need to explicitly pass -i ~/.ssh/id_rsa if sshagent manages it for ansible_ssh_private_key_file.
                            # Ensure main.yaml is in the 'ansible' directory or adjust path.
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
                // 'ssh-credentials' here is the same credential ID used for sshagent
                // The keyFileVariable will expose the path to the temporary private key file.
                withCredentials([sshUserPrivateKey(credentialsId: 'ssh-credentials', keyFileVariable: 'SSH_KEY')]) {
                    sh """
                        set -e
                        # Use the SSH_KEY variable provided by withCredentials
                        scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no ubuntu@${env.CONTROL_PLANE_IP}:/home/ubuntu/.kube/config kubeconfig
                        # Ensure env.CONTROL_PLANE_IP is set correctly from the previous stage
                        sed -i 's|server: https://.*:6443|server: https://${env.CONTROL_PLANE_IP}:6443|' kubeconfig
                    """
                }
            }
        }

        stage('Push Files to Git Repository') {
            // This stage is empty. If you intend to push changes (like kubeconfig, or updated state)
            // to a Git repository, you need to add git commands here.
            // Example:
            // steps {
            //     script {
            //         git config user.email "jenkins@example.com"
            //         git config user.name "Jenkins Automation"
            //         sh "git add kubeconfig terraform.tfstate" // Add files to commit
            //         sh "git commit -m 'Automated update from Jenkins pipeline'"
            //         withCredentials([usernamePassword(credentialsId: 'git-credentials', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
            //             sh "git push https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/barhe2/prometheus.git HEAD:main"
            //         }
            //     }
            // }
            when {
                expression { return env.MANIFEST_CHANGED }
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
            // Clean up temporary SSH key file and kubeconfig
            sh 'rm -f ~/.ssh/id_rsa || true' // This might not be necessary if sshagent manages it
            sh 'rm -f kubeconfig || true'
            // Ensure the temporary key file from withCredentials (SSH_KEY) is also cleaned up
            // Generally, Jenkins cleans up temp files from `withCredentials` automatically
            // but if you copy it, you need to clean up your copy.
        }
    }
}