pipeline {
    agent any

    // Prevent concurrent deployments to production
    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }

    environment {
        AWS_REGION     = 'eu-west-1'
        ECR_REPO       = 'damolak-devops-app'
        ECS_CLUSTER    = 'damolak-devops-app-cluster'
        ECS_SERVICE    = 'damolak-devops-app-service'
        TF_WORKING_DIR = 'terraform/environments/prod'
        IMAGE_TAG      = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
    }

    stages {

        //  Stage 1: Test 
        stage('Test') {
            steps {
                dir('app') {
                    sh '''
                        python3 -m venv .venv
                        . .venv/bin/activate
                        pip install --quiet -r requirements.txt
                        pytest test_app.py -v --tb=short
                    '''
                }
            }
            post {
                always {
                    dir('app') {
                        sh 'rm -rf .venv'
                    }
                }
            }
        }

        //  Stage 2: Build & Smoke Test 
        stage('Build & Smoke Test') {
            steps {
                dir('app') {
                    sh "docker build --build-arg APP_VERSION=${IMAGE_TAG} -t ${ECR_REPO}:${IMAGE_TAG} ."
                }
                sh '''
                    docker run -d --name smoke-test -p 8080:8080 ''' + "${ECR_REPO}:${IMAGE_TAG}" + '''
                    sleep 5
                    curl --fail http://localhost:8080/health || (docker logs smoke-test; docker rm -f smoke-test; exit 1)
                    docker rm -f smoke-test
                '''
            }
        }

        //  Stage 3: Push to ECR (main branch only) 
        stage('Push to ECR') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([[
                    $class:               'AmazonWebServicesCredentialsBinding',
                    credentialsId:        'aws-credentials',
                    accessKeyVariable:    'AWS_ACCESS_KEY_ID',
                    secretKeyVariable:    'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    script {
                        def accountId = sh(
                            script: 'aws sts get-caller-identity --query Account --output text',
                            returnStdout: true
                        ).trim()
                        env.ECR_REGISTRY = "${accountId}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                        env.IMAGE_URI    = "${env.ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"

                        sh """
                            aws ecr get-login-password --region ${AWS_REGION} \
                              | docker login --username AWS --password-stdin ${env.ECR_REGISTRY}

                            docker tag ${ECR_REPO}:${IMAGE_TAG} ${env.IMAGE_URI}
                            docker tag ${ECR_REPO}:${IMAGE_TAG} ${env.ECR_REGISTRY}/${ECR_REPO}:latest

                            docker push ${env.IMAGE_URI}
                            docker push ${env.ECR_REGISTRY}/${ECR_REPO}:latest

                            echo "Pushed: ${env.IMAGE_URI}"
                        """
                    }
                }
            }
        }

        //  Stage 4: Terraform Apply (main branch only) 
        stage('Terraform Apply') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([[
                    $class:               'AmazonWebServicesCredentialsBinding',
                    credentialsId:        'aws-credentials',
                    accessKeyVariable:    'AWS_ACCESS_KEY_ID',
                    secretKeyVariable:    'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    dir("${TF_WORKING_DIR}") {
                        sh 'terraform init'
                        sh "terraform plan -var='image_tag=${IMAGE_TAG}' -out=tfplan"
                        sh 'terraform apply -auto-approve tfplan'
                    }
                }
            }
        }

        //  Stage 5: Deploy to ECS (main branch only) 
        stage('Deploy to ECS') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([[
                    $class:               'AmazonWebServicesCredentialsBinding',
                    credentialsId:        'aws-credentials',
                    accessKeyVariable:    'AWS_ACCESS_KEY_ID',
                    secretKeyVariable:    'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh """
                        aws ecs update-service \
                          --cluster ${ECS_CLUSTER} \
                          --service  ${ECS_SERVICE} \
                          --force-new-deployment \
                          --region   ${AWS_REGION}

                        echo "Waiting for deployment to stabilise..."
                        aws ecs wait services-stable \
                          --cluster  ${ECS_CLUSTER} \
                          --services ${ECS_SERVICE} \
                          --region   ${AWS_REGION}

                        echo "Deployment stable. Image: ${env.IMAGE_URI}"
                    """
                }
            }
        }
    }

    //  Post-pipeline actions 
    post {
        success {
            echo "Pipeline succeeded for commit ${IMAGE_TAG}"
        }
        failure {
            echo "Pipeline FAILED for commit ${IMAGE_TAG} — check CloudWatch logs: /ecs/damolak-devops-app"
        }
        always {
            
            // Remove local Docker images to keep the agent disk clean
            sh """
                docker rmi ${ECR_REPO}:${IMAGE_TAG} || true
                docker rmi ${env.IMAGE_URI ?: ''} || true
            """
        }
    }
}
