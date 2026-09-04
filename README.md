# Aquarela - Desafio técnico

Infraestrutura como código (Terraform) para provisionar um cluster **AKS** na Azure e rodar a aplicação de demonstração **Sock Shop** (microsserviços), com ingress, TLS, e uma stack completa de observabilidade: métricas, logs e APM.

## Stack

| Camada | Ferramenta | Como foi instalado |
|---|---|---|
| Cluster | Azure Kubernetes Service (AKS) | Terraform |
| Ingress | ingress-nginx | Helm (via Terraform) |
| TLS | cert-manager (ClusterIssuer self-signed) | Helm (via Terraform) |
| Métricas | Prometheus + Grafana + Alertmanager | Helm `kube-prometheus-stack` (via Terraform) |
| Logs | Fluent Bit → Elasticsearch → Kibana | Helm (via Terraform) |
| APM | Elastic APM Server | Helm (via Terraform) |

---

## Arquitetura

A infraestrutura é executada no Azure Kubernetes Service (AKS). O tráfego externo entra pelo ingress-nginx, enquanto a observabilidade é dividida em três pipelines:

- **Métricas:** Prometheus → Grafana / Alertmanager
- **Logs:** Fluent Bit → Elasticsearch → Kibana
- **APM:** aplicação → APM Server → Elasticsearch → Kibana

---

## Como rodar do zero

### Pré-requisitos

- Conta Azure com uma subscription ativa
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) autenticado (`az login`)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- `kubectl`
- `helm` (opcional, útil para debug manual)

### 1. Clonar o repositório

```bash
git clone https://github.com/QueijoQualho/Aquarela-projeto.git
cd Aquarela-projeto/infra/environments/dev
```

### 2. Inicializar o Terraform

```bash
terraform init
```

### 3. Aplicar a infraestrutura 

> Importante: Para a integração do APM com o Elasticsearch foi utilizado um null_resource para a execução de comandos para a instalação da Integração do APM com o Elasticsearch sem precisar rodar um script separado, portanto a aplicação roda em 2 etapas: primeiro, o cluster AKS é provisionado, e depois as credenciais são obtidas e o resto da infraestrutura é aplicado.

```bash
# 1ª rodada: só o cluster AKS
terraform apply -target=module.aks

# 2ª rodada: obter credenciais do AKS e aplicar o resto da infraestrutura
az aks get-credentials --resource-group rg-aks-dev --name aks-dev --overwrite-existing
terraform apply -auto-approve
```

### 4. Descobrir os IPs e configurar acesso local

```bash
terraform output
```

Isso mostra o IP público do ingress-nginx. Adiciona no seu `/etc/hosts` (ajustando o IP):

```
<IP-DO-INGRESS> sockshop.local
<IP-DO-INGRESS> grafana.local
<IP-DO-INGRESS> kibana.local
```

### 5. Acessar tudo

| Serviço | URL | Credenciais |
|---|---|---|
| Sock Shop | `https://sockshop.local` | — |
| Grafana | `https://grafana.local` | `admin` / senha definida no `values` do módulo |
| Kibana | `https://kibana.local` | `elastic` / obtida via `kubectl get secret elasticsearch-master-credentials -n logging -o jsonpath='{.data.password}' \| base64 -d` |

Como os certificados são **self-signed** (sem domínio real), o navegador vai avisar sobre certificado inválido — é esperado, basta prosseguir mesmo assim.


### Comandos Utilizados no Teste do APM
Como as Imagens do Sock Shop não tem o APM integrado, é necessário adicionar manualmente.

```bash
kubectl run apm-test --rm -i --image=curlimages/curl -n logging --restart=Never --   sh -c 'curl -X POST "http://apm-server-apm-server:8200/intake/v2/events" -H "Content-Type: application/x-ndjson" --data-binary "{\"metadata\": {\"service\": {\"name\": \"front-end\", \"agent\": {\"name\": \"manual-test\", \"version\": \"1.0\"}}}}
{\"transaction\": {\"id\": \"0102030405060708\", \"trace_id\": \"0102030405060708090a0b0c0d0e0f10\", \"name\": \"GET /\", \"type\": \"request\", \"duration\": 32.5, \"span_count\": {\"started\": 0}}}"'
```

```bash
kubectl exec -it elasticsearch-master-0 -n logging -- \
curl -s -k -u "elastic:$(kubectl get secret elasticsearch-master-credentials -n logging -o jsonpath='{.data.password}' | base64 -d)" \
"https://localhost:9200/traces-apm*/_search?q=service.name:front-end"
```

---

## Estrutura do repositório

```
infra/
├── modules/
│   ├── aks/              # cluster AKS + resource group
│   ├── ingress-nginx/    # ingress-nginx via Helm + IP público estático
│   ├── cert-manager/     # cert-manager + ClusterIssuer self-signed
│   ├── monitoring/       # kube-prometheus-stack (Prometheus/Grafana/Alertmanager) + PrometheusRule customizado
│   ├── logging/          # Fluent Bit + Elasticsearch + Kibana + APM Server
│   └── sock-shop/        # Sock Shop (microservices-demo) via kubectl
└── environments/
    └── dev/
        ├── main.tf        # chama todos os módulos
        ├── providers.tf   # azurerm, kubernetes, helm, kubectl
        ├── variables.tf
        ├── backend.tf     # backend local
        └── outputs.tf

manifests/                 # YAMLs da Sock Shop
```

---

## Decisões de design e por quê

**Backend local em vez de remoto (Azure Storage Account).**
Não há necessidade de state compartilhado em equipe nesse projeto, então backend local foi suficiente e evitou o trabalho de provisionar um Storage Account só para isso.

**cert-manager com `ClusterIssuer` self-signed**
Como o ambiente não possui um domínio público, foi utilizado um ClusterIssuer do tipo selfSigned. Essa abordagem permite emitir certificados TLS para os serviços internos sem depender de um domínio público ou da validação http01 do Let's Encrypt, sendo adequada para o ambiente de desenvolvimento e demonstração do projeto.

**Utilização do `kubectl_manifest` (provider `alekc/kubectl`)**
O provider `kubernetes_manifest` nativo faz introspecção do schema do CRD no momento do `plan`/`apply`/`destroy`, o que causa falhas recorrentes quando o CRD (`ClusterIssuer`, criado pelo cert-manager) ainda não está totalmente registrado na API do cluster. O `kubectl_manifest` aplica de forma mais direta, sem essa validação, evitando o problema.

**Elasticsearch de nó único, sem persistência (`emptyDir`).**
Reduz drasticamente a complexidade (sem StorageClass/PVC) e o consumo de recursos, ao custo de perder os logs se o pod reiniciar — uma troca aceitável para demonstrar o requisito, não para produção.

**Alerta customizado com `kube-state-metrics`**
O alerta utiliza `kube_deployment_status_replicas_available` para detectar Deployments com réplicas indisponíveis, sem depender de ServiceMonitor ou PodMonitor nos microsserviços da Sock Shop.

**APM: coleta habilitada e validada**
O APM Server foi instalado e integrado ao Elasticsearch/Kibana. A coleta foi validada por meio de um evento de teste enviado via `curl`, demonstrando o funcionamento do pipeline de APM.

---

## Dificuldades encontradas

- **Health probe do Azure Load Balancer marcando o ingress-nginx como "unhealthy"**, mesmo com toda a configuração de rede (NSG, regras de LB, backend pool) aparentemente correta — causando timeout de conexão sem nenhum erro óbvio. Causa raiz: o probe testava o path `/` na porta de tráfego normal, e como o ingress-nginx retorna 404/308 nesse path sem um `Host` correspondente, o Azure interpretava isso como falha de saúde. Resolvido apontando o probe para `/healthz` via annotation.
- **Provider `alekc/kubectl` (a partir da v2.3) parou de tolerar valores de conexão "ainda não conhecidos"** no momento de configurar o provider — quebrando o padrão de cluster+manifests no mesmo apply. Resolvido fixando `lazy_load = true`.
- **Tentativa de desabilitar segurança do Elasticsearch via `esConfig` não funcionou** — o chart ignora esse campo para esse propósito específico; o controle real é o campo de nível superior `protocol`. A tentativa de correção introduziu uma quebra pior (probe de readiness incompatível com o protocolo real do servidor), revertida depois.
- **Kibana recusando o usuário `elastic`:** durante a configuração, o Kibana apresentou problemas ao utilizar o usuário `elastic` para comunicação interna. A solução foi utilizar o mecanismo nativo do chart baseado em *service account token*, removendo a configuração manual que estava competindo com ele.
* **Instabilidade na inicialização do Kibana:** durante a implantação, o Kibana apresentou comportamento intermitente, iniciando normalmente em algumas execuções e falhando ou permanecendo indisponível em outras. Após reinicializações e ajustes na configuração do Elastic Stack, o serviço passou a iniciar corretamente.
- **APM Server sem integração do Fleet:** o erro (`precondition 'apm integration installed' failed`) não deixa isso óbvio à primeira vista; a mudança de arquitetura (Fleet passou a gerenciar os index templates a partir da 8.0) exigiu uma chamada extra à API do Kibana antes de qualquer dado poder ser indexado.
- **Drift na configuração do `default_node_pool` do AKS:** alterações detectadas pelo Azure em `upgrade_settings` faziam o Terraform considerar temporariamente o `kube_config` como desconhecido, causando falhas na inicialização dos providers `kubernetes`, `helm` e `kubectl` (`dial tcp [::1]:80: connect: connection refused`). O problema foi solucionado utilizando `lifecycle.ignore_changes` no campo afetado.

---

## O que eu faria diferente com mais tempo

- **Backend remoto (Azure Storage Account)** para o state, com lock e possibilidade de trabalho em equipe/CI.
- **Persistência real no Elasticsearch** (PVC sobre Azure Disk), para que os logs sobrevivam a reinícios de pod.
- **Instrumentação completa do `front-end`** com o agente `elastic-apm-node` embutido na imagem (documentado no processo, não executado por tempo), capturando transações reais de uso em vez de um evento de teste manual.
- **TLS com Let's Encrypt e domínio real**, em vez de certificado self-signed — mais representativo de um cenário de produção.
- **Gestão de segredos via Azure Key Vault + CSI driver**, em vez de ler credenciais do Elasticsearch via `data source` do Terraform (que deixa o valor gravado no state, ainda que fora do código-fonte).
- **Dimensionamento e autoscaling:** dimensionar melhor os recursos do cluster antes de adicionar a stack de observabilidade e utilizar mecanismos de autoscaling, como HPA ou KEDA, para ajustar automaticamente a quantidade de pods conforme a demanda. Em um cenário maior, também seria possível utilizar um node pool dedicado para os componentes de observabilidade.

### Link do Vídeo - Desmonstação do codigo

https://youtu.be/dtSjpolNm2Q
