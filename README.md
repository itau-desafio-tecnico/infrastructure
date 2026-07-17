# infrastructure

Infraestrutura como código (**Terraform**) que provisiona, na AWS, todo o ambiente de execução dos microsserviços [`order-service`](../order-service/README.md) e [`requester-service`](../requester-service/README.md): rede, banco de dados, mensageria, cluster ECS Fargate com load balancer e a stack de observabilidade (métricas, tracing e dashboards).

## Sumário

- [Escopo](#escopo)
- [Stack de tecnologia](#stack-de-tecnologia)
- [Arquitetura](#arquitetura)
- [Fluxos](#fluxos)
- [Recursos provisionados / outputs](#recursos-provisionados--outputs)
- [Configuração](#configuração)
- [Como executar](#como-executar)
- [Simplificações assumidas](#simplificações-assumidas)

## Escopo

Este repositório define, via Terraform, toda a infraestrutura AWS necessária para rodar o sistema **desafio-itau** em um ambiente (`dev` por padrão): VPC com sub-redes públicas/privadas, banco de dados PostgreSQL (um RDS por serviço), tópico SNS + fila SQS para o evento `OrderCreated`, cluster ECS Fargate com os serviços `order-service` e `requester-service` por trás de um Application Load Balancer, e uma stack de observabilidade self-hosted (OpenTelemetry Collector, Prometheus, Jaeger e Grafana).

Não inclui o bootstrap do próprio backend do Terraform (bucket S3 + tabela DynamoDB de lock) — isso é responsabilidade do repositório irmão `terraform-backend`, que deve ser aplicado uma única vez, antes deste.

## Stack de tecnologia

| Categoria | Tecnologia |
|---|---|
| IaC | Terraform >= 1.7 |
| Provider principal | `hashicorp/aws` ~> 5.60 |
| Provider auxiliar | `hashicorp/random` ~> 3.6 (geração de senhas) |
| Cloud | AWS (região padrão `sa-east-1`) |
| Backend de estado | S3 (`itau-desafio-tecnico-tfstate`) + lock via DynamoDB (`itau-desafio-tecnico-terraform-locks`), criados pelo repositório `terraform-backend` |
| Compute | ECS Fargate |
| Banco de dados | RDS PostgreSQL 16 (uma instância por serviço) |
| Mensageria | SNS (tópico `order-created`) + SQS (fila + DLQ) |
| Observabilidade | OpenTelemetry Collector, Prometheus, Jaeger, Grafana (containers próprios no ECS, sem serviços gerenciados da AWS) |
| Segredos | AWS Secrets Manager (credenciais de banco e senha do admin do Grafana) |

## Arquitetura

O módulo raiz (`terraform/main.tf`) orquestra seis módulos filhos em `terraform/modules/`, com dependência explícita entre eles:

```
network ──► security ──► database ──┐
                                     ├──► ecs ──► observability
                          messaging ─┘
```

| Módulo | Responsabilidade |
|---|---|
| [`network`](terraform/modules/network) | VPC, 2 sub-redes públicas + 2 privadas (uma AZ cada), Internet Gateway, NAT Gateway único e tabelas de rota |
| [`security`](terraform/modules/security) | Security Groups: `alb` (80, 3000 Grafana, 16686 Jaeger, público), `ecs_tasks` (tráfego do ALB + tráfego interno entre containers) e `rds` (5432 apenas a partir do `ecs_tasks`) |
| [`database`](terraform/modules/database) | Duas instâncias RDS PostgreSQL 16 (`order` e `requester`), subnet group privado, senhas geradas via `random_password` e armazenadas no Secrets Manager |
| [`messaging`](terraform/modules/messaging) | Tópico SNS `order-created`, fila SQS `order-processing` com DLQ (`maxReceiveCount=5`) inscrita no tópico |
| [`ecs`](terraform/modules/ecs) | 3 repositórios ECR (`order-service`, `requester-service`, `order-service-migration`), ALB com listener HTTP:80 e roteamento por path, task definitions/serviços Fargate dos dois microsserviços, roles IAM (execução + task role de cada serviço), service discovery (Cloud Map) e log groups no CloudWatch |
| [`observability`](terraform/modules/observability) | OTel Collector, Prometheus, Jaeger e Grafana, cada um como serviço Fargate próprio, registrados no mesmo namespace de service discovery (`internal.local`) |

Além dos módulos, o root também cria diretamente o `aws_ecs_cluster` e o namespace de service discovery privado (`aws_service_discovery_private_dns_namespace`, `internal.local`), compartilhados por todos os serviços.

## Fluxos

### Ordem de aplicação (dependências entre módulos)

1. `network` cria a VPC e sub-redes.
2. `security` cria os Security Groups, dependendo da VPC.
3. `database` e `messaging` são provisionados em paralelo — o primeiro depende de rede/segurança, o segundo é independente.
4. `ecs` depende de rede, segurança, banco e mensageria: cria o ALB, as task definitions (com variáveis de ambiente e segredos apontando para os endpoints/ARNs gerados pelos módulos anteriores) e os serviços Fargate.
5. `observability` depende do `ecs` (usa o mesmo ALB para expor Grafana/Jaeger) e do cluster/rede/segurança.

### Roteamento de tráfego (ALB)

O ALB único expõe três listeners:

| Porta | Destino | Path/health check |
|---|---|---|
| 80 | `order-service` (path `/py-order-service/*`) ou `requester-service` (path `/jv-requester-service/*`); qualquer outro path retorna `404 Fixed Response` | Health checks em `/py-order-service/health` e `/jv-requester-service/actuator/health` |
| 3000 | Grafana | health check `/api/health` |
| 16686 | Jaeger UI | health check `/` |

### Comunicação entre serviços

- `order-service` chama `requester-service` via service discovery interno: `http://requester-service.internal.local:8081/jv-requester-service` (variável `REQUESTER_SERVICE_URL` injetada na task definition), sem passar pelo ALB.
- Ambos os serviços exportam traces/métricas via OTLP/HTTP para `http://otel-collector.internal.local:4318`, que roteia traces para o Jaeger e métricas para o Prometheus (scrape); o Grafana consulta Prometheus e Jaeger como datasources provisionados automaticamente.
- Credenciais de banco são injetadas nas tasks via `secrets` (Secrets Manager), nunca em texto plano nas variáveis de ambiente.

### Pipeline de deploy (consumidor desta infraestrutura)

Os workflows de CI/CD do `order-service` e `requester-service` publicam imagens nos repositórios ECR criados pelo módulo `ecs` (`desafio-dev-order-service`, `desafio-dev-requester-service`, `desafio-dev-order-service-migration`) e forçam um novo deployment no cluster `desafio-dev-cluster`. Este repositório não contém pipeline próprio de CI/CD para `terraform plan`/`apply` — a aplicação é manual (ver [Como executar](#como-executar)).

## Recursos provisionados / outputs

Principais outputs do módulo raiz (`terraform/outputs.tf`):

| Output | Descrição |
|---|---|
| `alb_dns_name` | DNS do ALB — base URL de `/py-order-service*`, `/jv-requester-service*`, Grafana (`:3000`) e Jaeger (`:16686`) |
| `grafana_admin_secret_arn` | ARN do secret no Secrets Manager com a senha do usuário `admin` do Grafana |
| `ecs_cluster_name` | Nome do cluster ECS |
| `private_subnet_ids` | IDs das sub-redes privadas |
| `ecs_tasks_security_group_id` | Security Group usado pelas tasks Fargate |
| `order_service_ecr_url` / `requester_service_ecr_url` | URLs dos repositórios ECR dos serviços |
| `order_service_migration_ecr_url` / `order_service_migration_task_family` | Repositório ECR e família da task de migração Liquibase do `order-service` |

## Configuração

Variáveis do módulo raiz (`terraform/variables.tf`), configuráveis via `terraform.tfvars` (partir de `terraform.tfvars.example`):

| Variável | Padrão | Descrição |
|---|---|---|
| `aws_region` | `sa-east-1` | Região AWS |
| `environment` | `dev` | Nome do ambiente (usado no prefixo `desafio-${environment}` de todos os recursos) |
| `vpc_cidr` | `10.0.0.0/16` | CIDR da VPC |
| `order_service_image` | `""` | URI da imagem Docker do `order-service`; vazio na primeira aplicação, atualizado pelo pipeline de CI/CD |
| `requester_service_image` | `""` | URI da imagem Docker do `requester-service`; idem |
| `order_service_desired_count` | `1` | Réplicas desejadas do `order-service` |
| `requester_service_desired_count` | `1` | Réplicas desejadas do `requester-service` |
| `db_instance_class` | `db.t4g.micro` | Classe das instâncias RDS |

O estado remoto é fixo em `terraform/backend.tf` (bucket `itau-desafio-tecnico-tfstate`, chave `infra/terraform.tfstate`, lock via DynamoDB `itau-desafio-tecnico-terraform-locks`, região `sa-east-1`).

## Como executar

### Pré-requisito: backend do Terraform

O bucket S3 e a tabela DynamoDB usados como backend remoto são provisionados pelo repositório irmão `terraform-backend` e devem existir **antes** de aplicar este projeto:

```bash
cd ../terraform-backend/terraform
terraform init
terraform apply
```

### Aplicar a infraestrutura

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # ajuste conforme necessário
terraform init
terraform plan
terraform apply
```

Na primeira aplicação, `order_service_image` e `requester_service_image` ficam vazios — o módulo `ecs` usa `<repositório-ecr>:latest` como padrão, e o pipeline de CI/CD de cada serviço atualiza a task definition após o primeiro build da imagem.

### Destruir

```bash
terraform destroy
```

As instâncias RDS têm `skip_final_snapshot = true` e `deletion_protection = false` — dados são perdidos permanentemente ao destruir o ambiente.

## Simplificações assumidas

Documentado diretamente no código do módulo `observability` (ADR 0005): dado o escopo de um desafio técnico, a stack de observabilidade não usa armazenamento persistente (EFS) para Prometheus/Grafana — dados de métricas e dashboards são perdidos se a task reiniciar — e roda com uma única task por componente, sem alta disponibilidade. Logs de aplicação continuam via CloudWatch Logs (já configurado nas task definitions do módulo `ecs`); a stack self-hosted cobre apenas métricas e tracing.
