# 7-Day Hands-On Plan: AWS · Terraform · Kubernetes · Helm

**Goal:** get practical, working skills by building real things, not by memorising theory for exams or interviews.
**Time:** about 6–8 hours/day. Each day has a short **Learn** block (~1.5 hrs) and a longer **Build** block (~5 hrs).
**End result:** an app running on EKS, with the infrastructure created by Terraform and the app deployed by Helm.

```
Day 1-2: AWS  ──►  Day 3-4: Terraform  ──►  Day 5: Kubernetes  ──►  Day 6: Helm  ──►  Day 7: All together on EKS
```

---

## Day 0 – Setup (do this the night before, ~1 hr)

Run the setup script. It installs and configures every tool used in this plan (each step is explained in comments inside the script):

```bash
./devops.setup.sh
```

- Create an AWS account. Turn on MFA for root, create an IAM user or SSO admin, then run `aws configure`.
- **Create a Budget alarm at $10.** EKS, NAT Gateways and load balancers charge by the hour.
- Install Docker Desktop (kind needs it).
- Work inside `~/projects/learning/devops-hands-on/`. The script creates the `aws/`, `terraform/`, `k8s/`, `helm/` and `capstone/` folders there, set up as a git repo.

---

## Day 1 – AWS Core: IAM, VPC, EC2

**Learn (1.5 hrs)**
- Regions vs Availability Zones (AZs)
- IAM: users, roles, policies, and the difference between a role and a user
- VPC: subnets (public vs private), route tables, Internet Gateway, NAT Gateway, Security Groups

**Build (5 hrs)**. Do this in the **console** first so you can see how the pieces fit together:
- [ ] Create a VPC with 2 public and 2 private subnets across 2 AZs
- [ ] Attach an Internet Gateway and set up route tables by hand
- [ ] Launch an EC2 instance in a public subnet with a user-data script that installs nginx
- [ ] Open port 80 in the Security Group and load the page in your browser
- [ ] Connect with **SSM Session Manager** instead of SSH keys, using an instance role with `AmazonSSMManagedInstanceCore`
- [ ] Repeat a few steps with the CLI: `aws ec2 describe-instances`, `aws ec2 describe-vpcs`

**Done when:** nginx loads in your browser from your EC2 instance.

---

## Day 2 – AWS Services: S3, RDS, ALB, Auto Scaling

**Learn (1.5 hrs)**
- S3 basics: buckets, policies, versioning
- ALB + Target Groups + Auto Scaling Group (ASG)
- RDS basics: subnet groups, why the database goes in a private subnet

**Build (5 hrs)**
- [ ] S3: create a bucket and upload files with `aws s3 cp` / `aws s3 sync`. Host a static site on it.
- [ ] Create a Launch Template from your Day 1 nginx setup, then an ASG (min 2) behind an **ALB**
- [ ] Terminate one instance and watch the ASG replace it
- [ ] Launch a small RDS Postgres instance in a private subnet. Connect to it from EC2 with `psql`.
- [ ] Look at the CloudWatch metrics for the ALB and the EC2 instances
- [ ] **Delete everything by hand.** Notice how tedious that is. Tomorrow you'll see why Terraform helps.

**Done when:** the ALB DNS name serves your page from 2 instances and survives one being killed.

---

## Day 3 – Terraform Basics

**Learn (1.5 hrs)**
- Providers, resources, variables, outputs, data sources
- The workflow: `init → plan → apply → destroy`
- What state is and why it matters

**Build (5 hrs)**
- [ ] Write Terraform to create an S3 bucket. Run `plan` and `apply`, look at `terraform.tfstate`, then `destroy`.
- [ ] Recreate the **Day 1 VPC + EC2 + nginx** in Terraform:
  - `variables.tf` (region, CIDR, instance type)
  - `main.tf` (VPC, subnets, IGW, routes, SG, EC2)
  - `outputs.tf` (public IP, URL)
- [ ] Change the instance type, run `plan`, and read the diff
- [ ] Use `count` or `for_each` to create the subnets instead of copy-pasting

```bash
terraform fmt && terraform validate && terraform plan && terraform apply
```

**Done when:** `terraform apply` builds the whole Day 1 setup and `terraform destroy` removes it cleanly.

---

## Day 4 – Terraform for Real: State, Modules, Registry

**Learn (1.5 hrs)**
- Remote state: S3 backend with locking
- Modules: writing your own and using Registry modules
- `terraform import` and `terraform state list/show`

**Build (5 hrs)**
- [ ] Create an S3 bucket for state and switch your backend to it (`use_lockfile = true`)
- [ ] Refactor your VPC code into a local module `modules/vpc`, and call it from `envs/dev`
- [ ] Replace your hand-written VPC with the Registry module `terraform-aws-modules/vpc/aws`, and compare how much code each needs
- [ ] Recreate **Day 2's ALB + ASG** with Terraform
- [ ] Create one resource by hand in the console, then `terraform import` it
- [ ] `terraform destroy` everything except the state bucket

**Done when:** your Day 1 + Day 2 infrastructure comes up from a single `apply` with remote state.

---

## Day 5 – Kubernetes (Local with kind)

**Learn (1.5 hrs)**
- Pods, Deployments, Services, Ingress, ConfigMaps, Secrets, Namespaces
- How they connect: Deployment → ReplicaSet → Pods, and Service → Pods via labels

**Build (5 hrs)**
```bash
kind create cluster --name learn
kubectl get nodes
```
- [ ] Deploy nginx with `kubectl create deployment`, then write the same thing as a YAML manifest
- [ ] Expose it with a Service and reach it with `kubectl port-forward`
- [ ] Scale to 3 replicas, change the image tag, then use `kubectl rollout status` and `kubectl rollout undo`
- [ ] Add a ConfigMap (env vars) and a Secret, and mount them in the Pod
- [ ] Add liveness/readiness probes and resource requests/limits
- [ ] Install an NGINX ingress controller and route `/app1` and `/app2` to two different services
- [ ] **Break things on purpose and fix them:** a wrong image tag (ImagePullBackOff), a bad command (CrashLoopBackOff), huge resource requests (Pending)

Commands you'll use all day:
```bash
kubectl get pods -A
kubectl describe pod <name>
kubectl logs <pod> -f
kubectl get events --sort-by=.lastTimestamp
kubectl exec -it <pod> -- sh
k9s
```

**Done when:** a 2-service app with Ingress, config and probes is running, and you can debug a failing pod.

---

## Day 6 – Helm

**Learn (1 hr)**
- Charts, releases, values, and repos
- Template basics: `{{ .Values.x }}`, `{{ include }}`, `if`, `range`

**Build (5.5 hrs)**
- [ ] Install a community chart: `helm repo add bitnami https://charts.bitnami.com/bitnami`, then `helm install my-redis bitnami/redis`
- [ ] Try `helm list`, `helm upgrade --set ...`, `helm history`, `helm rollback`, and `helm uninstall`
- [ ] `helm create myapp`, and read through each generated file
- [ ] Convert your **Day 5 manifests** into this chart:
  - make the image, replicas, resources, ingress host and env vars come from `values.yaml`
  - create `values-dev.yaml` and `values-prod.yaml`
- [ ] Use `helm template` and `helm lint` to check the output before installing
- [ ] Install the chart into kind with `helm upgrade --install myapp ./myapp -f values-dev.yaml`
- [ ] Bump the chart version, upgrade, then roll back

**Done when:** one Helm command deploys your full app, with different settings for dev and prod.

---

## Day 7 – Capstone: EKS + Terraform + Helm

**Build the whole day (~7 hrs)**

1. **Infrastructure with Terraform** (`capstone/infra`)
   - [ ] VPC with the `terraform-aws-modules/vpc/aws` module (2 AZs, single NAT Gateway to save money)
   - [ ] EKS with the `terraform-aws-modules/eks/aws` module and 1 small managed node group (t3.medium × 2)
   - [ ] ECR repository for your app image
   - [ ] `aws eks update-kubeconfig --name <cluster>`, then `kubectl get nodes`

2. **Cluster add-ons with Helm**
   - [ ] AWS Load Balancer Controller (needs an IAM role for its service account, created with Terraform)
   - [ ] Optional: metrics-server, so the HPA has metrics to work with

3. **Deploy your app**
   - [ ] Build a simple app image and push it to ECR
   - [ ] `helm upgrade --install myapp ./myapp -f values-prod.yaml`, with an Ingress of class `alb`
   - [ ] Open the ALB URL in your browser 🎉
   - [ ] Add an HPA and generate load, then watch the pods scale

4. **Clean up (mandatory)**
   - [ ] `helm uninstall` everything first, so the ALBs get deleted
   - [ ] `terraform destroy`
   - [ ] Check the EC2, ELB, NAT Gateway and EKS pages in the console to confirm nothing is left running

**Done when:** a public URL serves your app from EKS, everything was built from code, and it has all been torn down again.

---

## Quick reference

| Tool | Docs to keep open |
|---|---|
| AWS | docs.aws.amazon.com, plus `aws <service> help` |
| Terraform | registry.terraform.io (look at provider docs and module examples) |
| Kubernetes | kubernetes.io/docs/reference/kubectl/quick-reference |
| Helm | helm.sh/docs/chart_template_guide |
| EKS | eksworkshop.com |

## Tips for the week
- **Type the code yourself.** Don't copy-paste whole files. Fixing your own errors is how you learn.
- Put each day's code in git, so that by Day 7 you have a portfolio repo.
- If you get stuck for more than 30 minutes, check the Registry module examples or the official docs.
- **Destroy AWS resources at the end of every day.** Kubernetes and Helm practice is free on kind.
- Expected AWS cost for the week, if you clean up daily: **about $5–15**. Most of it comes from the Day 7 EKS cluster and NAT Gateway.
