pipeline {
    agent any
    
    environment {
        AWS_REGION = 'us-east-1'
        NEXUS_URL = 'https://nexus.internal:8081'
        NEXUS_REPO = 'smartie-prm-docker'
        GITOPS_REPO = 'hdt98/smartie-prm-gitops'
        APP_NAME = 'smartie-prm'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Build Dependencies') {
            steps {
                script {
                    sh '''
                        # Install Python dependencies
                        pip install -r enterprise_service/indexing_worker/requirements.txt
                        
                        # Install Node dependencies for plugin
                        cd openviking/plugin
                        npm install
                    '''
                }
            }
        }
        
        stage('Test') {
            steps {
                script {
                    parallel(
                        'Python Tests': {
                            sh 'pytest tests/ -v'
                        },
                        'TypeScript Tests': {
                            sh 'cd openviking/plugin && npm test'
                        }
                    )
                }
            }
        }
        
        stage('Security Scan') {
            steps {
                script {
                    // Trivy vulnerability scanner
                    sh 'trivy fs --security-checks vuln,config .'
                    
                    // SonarQube scan (if configured)
                    // sh 'mvn sonar:sonar'
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    def imageTag = sh(
                        script: "echo ${GIT_COMMIT.take(7)}",
                        returnStdout: true
                    ).trim()
                    
                    env.IMAGE_TAG = imageTag
                    
                    sh """
                        docker build \
                            -t ${NEXUS_URL}/${NEXUS_REPO}:${imageTag} \
                            -t ${NEXUS_URL}/${NEXUS_REPO}:latest \
                            -f enterprise_service/Dockerfile \
                            .
                    """
                }
            }
        }
        
        stage('Push to Nexus') {
            steps {
                script {
                    sh """
                        # Login to Nexus (configure credentials in Jenkins)
                        docker login ${NEXUS_URL} -u \${NEXUS_USER} -p \${NEXUS_PASS}
                        
                        # Push images
                        docker push ${NEXUS_URL}/${NEXUS_REPO}:${IMAGE_TAG}
                        docker push ${NEXUS_URL}/${NEXUS_REPO}:latest
                    """
                }
            }
        }
        
        stage('Update GitOps') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                }
            }
            steps {
                script {
                    sh """
                        # Clone GitOps repo
                        git clone https://github.com/${GITOPS_REPO}.git /tmp/gitops
                        cd /tmp/gitops
                        
                        # Update image tag in values.yaml
                        sed -i "s|image: .*${APP_NAME}:.*|image: ${NEXUS_URL}/${NEXUS_REPO}:${IMAGE_TAG}|" k8s/overlays/prod/values.yaml
                        
                        # Commit and push
                        git config user.email "jenkins@smartie.local"
                        git config user.name "Jenkins"
                        git add k8s/overlays/prod/values.yaml
                        git diff --staged --quiet || git commit -m "Update ${APP_NAME} to ${IMAGE_TAG}"
                        git push
                    """
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed!'
        }
    }
}
