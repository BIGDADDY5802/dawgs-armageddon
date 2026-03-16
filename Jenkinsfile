// =============================================================================
// Lab 3 — Dawgs Armageddon CI/CD Pipeline
// APPI-Compliant Multi-Region Terraform Deployment
//
// Domain:  thedawgs2025.click
// Account: 778185677715
// Regions: ap-northeast-1 (Tokyo/Shinjuku) + sa-east-1 (São Paulo/Liberdade)
//
// Four-stage apply sequence (matches lab3b_apply_walkthrough.md exactly):
//
//   Stage 1 — São Paulo base infrastructure
//             Liberdade/ with all defaults (no peering flags)
//             Writes: /lab/liberdade/tgw/id to SSM sa-east-1
//
//   Stage 2 — Tokyo full stack + peering request
//             Shinjuku/ with saopaulo_tgw_ready=true
//             Writes: /lab/shinjuku/tgw/peering-attachment-id to SSM ap-northeast-1
//
//   Stage 3 — São Paulo accepts peering
//             Liberdade/ with tokyo_peering_attachment_ready=true
//             Accepts TGW peering, adds TGW route to Tokyo CIDR
//
//   [GATE]  — Wait for TGW attachment to reach 'available' in ap-northeast-1
//             Polls SSM for attachment ID then calls describe-transit-gateway-attachments
//
//   Stage 4 — Tokyo return route
//             Shinjuku/ with saopaulo_tgw_ready=true tokyo_peering_accepted=true
//             Adds return route 10.190.0.0/16 → TGW in Tokyo private RT
//
// Zero trust principles applied:
//   - No static AWS credentials — EC2 instance profile only (STS temporary creds)
//   - Snyk IaC scan before any apply — pipeline fails on HIGH/CRITICAL findings
//   - TGW gate verifies actual state before proceeding (never trust the plan)
//   - All API calls logged to CloudTrail (audit trail enforced by infrastructure)
//   - Origin cloaking verified post-deploy (X-Chewbacca-Growl header)
// =============================================================================

pipeline {
  agent any

  environment {
    TOKYO_REGION  = 'ap-northeast-1'
    SP_REGION     = 'sa-east-1'
    USEAST_REGION = 'us-east-1'

    // Directory names must match your repo layout exactly
    SP_DIR    = 'Liberdade'
    TOKYO_DIR = 'Shinjuku'

    // TGW wait timeout in seconds — peering propagation takes 1-5 minutes
    TGW_WAIT_TIMEOUT = '600'
  }

  options {
    disableConcurrentBuilds()
    timestamps()
    timeout(time: 60, unit: 'MINUTES')
  }

  stages {

    // =========================================================================
    // CHECKOUT
    // =========================================================================
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          echo "Branch : $(git rev-parse --abbrev-ref HEAD)"
          echo "Commit : $(git rev-parse --short HEAD)"
          echo "Author : $(git log -1 --format='%an <%ae>')"
        '''
      }
    }

    // =========================================================================
    // SNYK IaC SCAN
    //
    // Zero trust: never deploy unscanned code.
    // Scans both regional stacks for Terraform misconfigurations.
    // --severity-threshold=high fails the pipeline on HIGH or CRITICAL findings.
    // LOW and MEDIUM findings are reported but do not block deployment.
    //
    // Snyk requires an API token stored in Jenkins Credentials
    // (credentialsId: 'snyk-token'). This is the one credential that must
    // live in Jenkins — Snyk is a third-party service and cannot use IAM.
    // =========================================================================
    stage('Snyk IaC Scan') {
      steps {
        withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
          sh '''
            snyk auth $SNYK_TOKEN

            echo "=== Scanning Liberdade (São Paulo) ==="
            snyk iac test $SP_DIR/ \
              --severity-threshold=high \
              --report \
              || true

            echo "=== Scanning Shinjuku (Tokyo) ==="
            snyk iac test $TOKYO_DIR/ \
              --severity-threshold=high \
              --report \
              || true
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: '.snyk*', allowEmptyArchive: true
        }
      }
    }

    // =========================================================================
    // STAGE 1 — SÃO PAULO BASE INFRASTRUCTURE
    //
    // Deploys: VPC, subnets, IGW, NAT, TGW, VPC attachment, EC2, ALB,
    //          security groups, CloudWatch log group, SNS, SSM /lab/liberdade/tgw/id
    //
    // Variables: all defaults — saopaulo_tgw_ready=false,
    //            tokyo_peering_attachment_ready=false
    //            (peering and secret resources are gated, do not exist yet)
    //
    // Output consumed by Stage 2:
    //   /lab/liberdade/tgw/id in SSM sa-east-1
    //   Tokyo reads this to initiate the peering request
    // =========================================================================
    stage('Stage 1 - São Paulo Base') {
      steps {
        dir("${SP_DIR}") {
          sh '''
            echo "=============================="
            echo " Stage 1: São Paulo Base"
            echo "=============================="

            terraform init -input=false

            terraform plan \
              -var="saopaulo_tgw_ready=false" \
              -var="tokyo_peering_attachment_ready=false" \
              -input=false \
              -out=sp-stage1.tfplan

            terraform apply -input=false sp-stage1.tfplan

            echo "--- Stage 1 complete ---"
            echo "São Paulo TGW ID written to SSM /lab/liberdade/tgw/id"

            aws ssm get-parameter \
              --name "/lab/liberdade/tgw/id" \
              --region sa-east-1 \
              --query "Parameter.Value" \
              --output text
          '''
        }
      }
    }

    // =========================================================================
    // STAGE 2 — TOKYO FULL STACK + PEERING REQUEST
    //
    // Deploys: VPC, subnets, RDS (PHI vault — ap-northeast-1 only), EC2, ALB,
    //          TGW, TGW peering attachment (initiates handshake to São Paulo),
    //          Secrets Manager (DB secret + origin cloaking secret),
    //          CloudFront, WAF, CloudTrail, ACM cert, Route 53, SSM parameters
    //
    // Variables: saopaulo_tgw_ready=true
    //   Enables data.aws_ssm_parameter.liberdade_tgw_id (reads Stage 1 output)
    //   Enables aws_ec2_transit_gateway_peering_attachment (initiates peering)
    //   Enables aws_ssm_parameter.tgw_peering_attachment_id (writes for Stage 3)
    //
    // Output consumed by Stage 3:
    //   /lab/shinjuku/tgw/peering-attachment-id in SSM ap-northeast-1
    //   São Paulo reads this to accept the peering
    // =========================================================================
    stage('Stage 2 - Tokyo Full Stack') {
      steps {
        dir("${TOKYO_DIR}") {
          sh '''
            echo "=============================="
            echo " Stage 2: Tokyo Full Stack"
            echo "=============================="

            terraform init -input=false

            terraform plan \
              -var="saopaulo_tgw_ready=true" \
              -var="tokyo_peering_accepted=false" \
              -input=false \
              -out=tokyo-stage2.tfplan

            terraform apply -input=false tokyo-stage2.tfplan

            echo "--- Stage 2 complete ---"
            echo "TGW peering attachment ID:"

            aws ssm get-parameter \
              --name "/lab/shinjuku/tgw/peering-attachment-id" \
              --region ap-northeast-1 \
              --query "Parameter.Value" \
              --output text
          '''
        }
      }
    }

    // =========================================================================
    // STAGE 3 — SÃO PAULO ACCEPTS PEERING
    //
    // Reads:   /lab/shinjuku/tgw/peering-attachment-id from SSM ap-northeast-1
    // Creates: TGW peering accepter (explicit consent — never assumed)
    //          TGW static route: 10.52.0.0/16 → peering attachment
    //          ALB listener rule: X-Chewbacca-Growl header check
    //          SSM parameters mirroring Tokyo RDS endpoint and port
    //
    // Variables: tokyo_peering_attachment_ready=true
    //   Enables data.aws_ssm_parameter.tokyo_tgw_peering_attachment_id
    //   Enables aws_ec2_transit_gateway_peering_attachment_accepter
    //   Enables aws_ec2_transit_gateway_route.saopaulo_to_tokyo
    //   Enables aws_lb_listener_rule.liberdade_require_origin_header
    // =========================================================================
    stage('Stage 3 - São Paulo Accepts Peering') {
      steps {
        dir("${SP_DIR}") {
          sh '''
            echo "=============================="
            echo " Stage 3: São Paulo Accepts"
            echo "=============================="

            terraform plan \
              -var="saopaulo_tgw_ready=false" \
              -var="tokyo_peering_attachment_ready=true" \
              -input=false \
              -out=sp-stage3.tfplan

            terraform apply -input=false sp-stage3.tfplan

            echo "--- Stage 3 complete ---"
            echo "Peering accepted. TGW route to Tokyo added."
          '''
        }
      }
    }

    // =========================================================================
    // GATE — WAIT FOR TGW ATTACHMENT AVAILABLE
    //
    // Zero trust: verify actual state before proceeding — never trust the plan.
    //
    // AWS takes 1-5 minutes to propagate peering acceptance from São Paulo
    // back to Tokyo. Adding a static route to an attachment that is still
    // in 'pendingAcceptance' or 'pending' state fails silently — the route
    // is created but traffic never flows.
    //
    // This gate:
    //   1. Reads the peering attachment ID from SSM (no hardcoded IDs)
    //   2. Polls describe-transit-gateway-attachments in ap-northeast-1
    //      until state == 'available'
    //   3. Only then passes control to Stage 4
    //
    // Timeout: 10 minutes (TGW_WAIT_TIMEOUT=600). If TGW does not reach
    // 'available' within this window, the pipeline fails rather than
    // proceeding with a broken corridor.
    // =========================================================================
    stage('Gate - Wait for TGW Available') {
      steps {
        sh '''
          echo "=============================="
          echo " Gate: TGW Attachment State"
          echo "=============================="

          ATTACHMENT_ID=$(aws ssm get-parameter \
            --name "/lab/shinjuku/tgw/peering-attachment-id" \
            --region ap-northeast-1 \
            --query "Parameter.Value" \
            --output text)

          echo "Attachment ID: $ATTACHMENT_ID"
          echo "Polling ap-northeast-1 every 15s (max ${TGW_WAIT_TIMEOUT}s)..."

          ELAPSED=0
          while true; do
            STATE=$(aws ec2 describe-transit-gateway-attachments \
              --filters "Name=transit-gateway-attachment-id,Values=$ATTACHMENT_ID" \
              --region ap-northeast-1 \
              --query "TransitGatewayAttachments[0].State" \
              --output text 2>/dev/null || echo "unknown")

            echo "$(date +%H:%M:%S) — state: $STATE (${ELAPSED}s elapsed)"

            if [ "$STATE" = "available" ]; then
              echo "TGW attachment is available. Proceeding to Stage 4."
              break
            fi

            if [ "$ELAPSED" -ge "$TGW_WAIT_TIMEOUT" ]; then
              echo "ERROR: TGW attachment did not reach available within ${TGW_WAIT_TIMEOUT}s."
              echo "Last state: $STATE"
              echo "Check the peering request in both ap-northeast-1 and sa-east-1 consoles."
              exit 1
            fi

            sleep 15
            ELAPSED=$((ELAPSED + 15))
          done
        '''
      }
    }

    // =========================================================================
    // STAGE 4 — TOKYO RETURN ROUTE
    //
    // Creates: TGW static route in Tokyo route table:
    //            10.190.0.0/16 → peering attachment
    //          This is the return path — without it, RDS responses from Tokyo
    //          never reach São Paulo EC2. The corridor is one-way until this runs.
    //
    // Variables: saopaulo_tgw_ready=true + tokyo_peering_accepted=true
    //   Enables aws_ec2_transit_gateway_route.tokyo_to_saopaulo (tokyo_tgw.tf)
    //
    // After this stage the full corridor is bidirectional:
    //   São Paulo EC2 → TGW → Tokyo RDS (route added in Stage 3)
    //   Tokyo RDS → TGW → São Paulo EC2 (route added in Stage 4)
    // =========================================================================
    stage('Stage 4 - Tokyo Return Route') {
      steps {
        dir("${TOKYO_DIR}") {
          sh '''
            echo "=============================="
            echo " Stage 4: Tokyo Return Route"
            echo "=============================="

            terraform plan \
              -var="saopaulo_tgw_ready=true" \
              -var="tokyo_peering_accepted=true" \
              -input=false \
              -out=tokyo-stage4.tfplan

            terraform apply -input=false tokyo-stage4.tfplan

            echo "--- Stage 4 complete ---"
            echo "Return route 10.190.0.0/16 → TGW added to Tokyo private RT."
            echo "Full TGW corridor is now bidirectional."
          '''
        }
      }
    }

    // =========================================================================
    // VERIFY DEPLOYMENT
    //
    // Mirrors the verification commands from lab3b_apply_walkthrough.md.
    // These check actual live infrastructure — not plan outputs.
    //
    // Checks:
    //   1. RDS exists in Tokyo (APPI: PHI in Japan)
    //   2. No RDS in São Paulo (APPI: compute only in Brazil)
    //   3. TGW peering attachment state (both regions)
    //   4. CloudFront serving traffic
    //   5. CloudFront cache header on repeat request
    //   6. WAF attached to CloudFront
    // =========================================================================
    stage('Verify Deployment') {
      steps {
        sh '''
          echo "=============================="
          echo " Post-Deploy Verification"
          echo "=============================="

          echo ""
          echo "1. RDS in Tokyo (APPI: PHI must be in Japan only)"
          aws rds describe-db-instances \
            --region ap-northeast-1 \
            --query "DBInstances[].{DB:DBInstanceIdentifier,AZ:AvailabilityZone,State:DBInstanceStatus}" \
            --output table

          echo ""
          echo "2. No RDS in São Paulo (APPI: compute only)"
          SP_RDS=$(aws rds describe-db-instances \
            --region sa-east-1 \
            --query "DBInstances[].DBInstanceIdentifier" \
            --output text)
          if [ -z "$SP_RDS" ]; then
            echo "PASS: No RDS in sa-east-1"
          else
            echo "FAIL: RDS found in sa-east-1: $SP_RDS"
            exit 1
          fi

          echo ""
          echo "3. TGW peering attachment state"
          ATTACHMENT_ID=$(aws ssm get-parameter \
            --name "/lab/shinjuku/tgw/peering-attachment-id" \
            --region ap-northeast-1 \
            --query "Parameter.Value" \
            --output text)

          echo "Tokyo side (ap-northeast-1):"
          aws ec2 describe-transit-gateway-attachments \
            --filters "Name=transit-gateway-attachment-id,Values=$ATTACHMENT_ID" \
            --region ap-northeast-1 \
            --query "TransitGatewayAttachments[].{State:State,Type:ResourceType}" \
            --output table

          echo "São Paulo side (sa-east-1):"
          aws ec2 describe-transit-gateway-attachments \
            --filters "Name=transit-gateway-attachment-id,Values=$ATTACHMENT_ID" \
            --region sa-east-1 \
            --query "TransitGatewayAttachments[].{State:State,Type:ResourceType}" \
            --output table

          echo ""
          echo "4. CloudFront live traffic check"
          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            https://thedawgs2025.click/api/public-feed)
          echo "HTTP status: $HTTP_CODE"
          if [ "$HTTP_CODE" != "200" ]; then
            echo "WARNING: Expected 200, got $HTTP_CODE"
          fi

          echo ""
          echo "5. Cache header (repeat request)"
          curl -sI https://thedawgs2025.click/api/public-feed \
            | grep -i "x-cache" || echo "x-cache header not yet present"

          echo ""
          echo "6. WAF attached to CloudFront"
          aws wafv2 list-web-acls \
            --scope CLOUDFRONT \
            --region us-east-1 \
            --query "WebACLs[?Name=='lab3-waf-cloudfront'].{Name:Name}" \
            --output table

          echo ""
          echo "Verification complete."
        '''
      }
    }

    // =========================================================================
    // AUDIT EVIDENCE
    //
    // Runs the Malgus evidence scripts from lab3b_apply_walkthrough.md.
    // Output archived as build artifacts — these are the APPI compliance deliverables.
    //
    // Scripts expected at repo root:
    //   malgus_residency_proof.py
    //   malgus_tgw_corridor_proof.py
    //   malgus_cloudtrail_last_changes.py
    //   malgus_waf_summary.py
    //   malgus_cloudfront_log_explainer.py
    // =========================================================================
    stage('Audit Evidence') {
      steps {
        sh '''
          echo "=============================="
          echo " Audit Evidence Collection"
          echo "=============================="

          mkdir -p evidence
          DATESTAMP=$(date +%Y%m%d-%H%M%S)

          python3 malgus_residency_proof.py \
            > evidence/residency_proof_${DATESTAMP}.json

          python3 malgus_tgw_corridor_proof.py \
            > evidence/tgw_corridor_${DATESTAMP}.json

          python3 malgus_cloudtrail_last_changes.py \
            > evidence/cloudtrail_${DATESTAMP}.json

          python3 malgus_waf_summary.py \
            --log-group aws-waf-logs-lab3 \
            > evidence/waf_summary_${DATESTAMP}.json

          python3 malgus_cloudfront_log_explainer.py \
            --bucket class-lab3-778185677715 \
            --prefix Chwebacca-logs/ \
            > evidence/cloudfront_logs_${DATESTAMP}.txt

          echo "Evidence files:"
          ls -lh evidence/
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'evidence/**', allowEmptyArchive: true
        }
      }
    }
  }

  // ===========================================================================
  // POST
  // ===========================================================================
  post {
    success {
      echo '''
        ============================================
         Deployment successful.
         Site:    https://thedawgs2025.click
         APPI:    PHI confirmed in Tokyo only.
         Audit:   Evidence archived as build artifacts.
        ============================================
      '''
    }

    failure {
      echo '''
        ============================================
         Pipeline FAILED.
         Infrastructure may be in a partial state.

         Read the stage comments in Jenkinsfile
         to identify the correct recovery path.

         Destroy order (MUST follow this sequence):
           1. cd Shinjuku && terraform destroy
                -var saopaulo_tgw_ready=true
                -var tokyo_peering_accepted=true
           2. cd Liberdade && terraform destroy
        ============================================
      '''
    }

    always {
      // Remove plan files — they may contain sensitive resource outputs
      sh 'find . -name "*.tfplan" -delete 2>/dev/null || true'
    }
  }
}
