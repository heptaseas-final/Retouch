pipeline {
    agent any

    options {
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        PATH = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
        PROJECT = 'Retouch.xcodeproj'
        SCHEME = 'Retouch'
        DESTINATION = 'platform=iOS Simulator,name=iPhone 17,OS=latest'
        LANG = 'en_US.UTF-8'
        LC_ALL = 'en_US.UTF-8'
    }

    stages {
        stage('Checkout'){
            steps {
                checkout scm
            }
        }

        stage('Unit Test') {
            steps {
                sh '''
                    xcodegen generate
                    xcrun simctl shutdown all || true
                    rm -rf build/Retouch.xcresult
                    set -o pipefail && xcodebuild test \
                        -project "$PROJECT" \
                        -scheme "$SCHEME" \
                        -destination "$DESTINATION" \
                        -derivedDataPath build/DerivedData \
                        -resultBundlePath build/Retouch.xcresult \
                        -parallel-testing-enabled NO \
                        -maximum-concurrent-test-simulator-destinations 1 \
                        | xcbeautify --report junit --report-path build/reports
                '''
            }
        }
    }

    post {
        always {
            junit allowEmptyResults: true, testResults: 'build/reports/junit.xml'
            archiveArtifacts artifacts: 'build/Retouch.xcresult/**', allowEmptyArchive: true
            cleanWs()
        }
        success {
            echo 'all Retouch testcases passed ✅'
        }
        failure {
            echo 'test case failed. please check the failed log ❌'
        }
    }
}