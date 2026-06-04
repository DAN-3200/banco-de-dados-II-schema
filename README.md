# Sistema de Agendamentos com Supabase

Um sistema robusto de gerenciamento de agendamentos construído com **Supabase** e **PostgreSQL**, permitindo agendamento de serviços com validação de disponibilidade de profissionais.

## 📋 Visão Geral

O projeto implementa um sistema completo de agendamentos onde clientes podem agendar serviços com profissionais disponíveis. Inclui:

- ✅ Validação de disponibilidade de profissionais
- ✅ Prevenção de conflitos de horários
- ✅ Log automático de operações
- ✅ View consolidada de agendamentos
- ✅ Políticas de segurança em nível de linha (RLS)

## 🗄️ Estrutura do Banco de Dados

### Tabelas

#### `servicos`
Catálogo de serviços disponíveis.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | INTEGER | Identificador único (PK) |
| `descricao` | TEXT | Descrição do serviço |
| `duracao` | INTERVAL | Duração do serviço |
| `preco` | NUMERIC(10,2) | Preço do serviço |

**Constraints:**
- `check_duracao_negativa`: Duração deve ser > 0
- `check_preco_negativo`: Preço deve ser > 0

#### `profissionais`
Profissionais que executam os serviços.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | INTEGER | Identificador único (PK) |
| `profissional` | TEXT | Nome do profissional |
| `id_servico` | INTEGER | Serviço que oferece (FK) |

#### `clientes`
Clientes que contratam os serviços.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | INTEGER | Identificador único (PK) |
| `cliente` | TEXT | Nome do cliente |
| `contato` | INTEGER | Informação de contato |

#### `agendamentos`
Registros de agendamentos realizados.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | INTEGER | Identificador único (PK) |
| `id_servico` | INTEGER | Serviço agendado (FK) |
| `id_profissional` | INTEGER | Profissional designado (FK) |
| `id_cliente` | INTEGER | Cliente (FK) |
| `data_atendimento` | TIMESTAMP | Data/hora do atendimento |
| `status` | TEXT | Status ('PENDENTE', 'CONCLUIDO', 'CANCELADO') |

**Constraints:**
- `check_horario_retroativo`: Não permite agendamentos no passado
- `agendamentos_status_check`: Apenas status válidos permitidos

#### `log_agendamentos`
Log de todas as operações em agendamentos.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | INTEGER | Identificador único (PK) |
| `tipo_operacao` | VARCHAR(10) | Tipo de operação (INSERT/UPDATE/DELETE) |
| `data_operacao` | TIMESTAMP | Data/hora da operação |

### Views

#### `v_agendamento`
View consolidada que integra informações de agendamentos com dados de serviços, profissionais e clientes.

```sql
SELECT
  servico,
  profissional,
  cliente,
  valor_servico,
  data_atendimento,
  duracao,
  data_fim,
  status
FROM v_agendamento;
```

## ⚙️ Funções e Procedures

### `fn_log_agendamento()`
Trigger que registra automaticamente todas as operações (INSERT, UPDATE, DELETE) na tabela `log_agendamentos`.

### `fn_verificar_disponibilidade(p_id_profissional, p_id_servico, p_data_atendimento)`
Verifica se um profissional tem disponibilidade em um horário específico.

**Parâmetros:**
- `p_id_profissional`: ID do profissional
- `p_id_servico`: ID do serviço
- `p_data_atendimento`: Data/hora desejada

**Retorna:** BOOLEAN (true se disponível, false caso contrário)

**Lógica:**
- Calcula a duração do serviço
- Verifica conflitos de horários com agendamentos não-cancelados
- Retorna disponibilidade

### `proc_realiza_agendamento(p_id_servico, p_id_profissional, p_id_cliente, p_data_atendimento)`
Function que realiza o agendamento com validação de disponibilidade.

**Parâmetros:**
- `p_id_servico`: ID do serviço
- `p_id_profissional`: ID do profissional
- `p_id_cliente`: ID do cliente
- `p_data_atendimento`: Data/hora do atendimento

**Retorna:** INTEGER (ID do agendamento criado)

**Exceções:**
- Lança erro se serviço não existir
- Lança erro se houver conflito de horário

### `proc_realizar_agendamento(p_id_servico, p_id_profissional, p_id_cliente, p_data_atendimento)`
Procedure alternativa para agendamento (não retorna ID).

## 🔐 Segurança

### Políticas de RLS (Row Level Security)

- **clientes**: Leitura habilitada para todos os usuários (anon, authenticated, service_role)
- **profissionais**: Leitura habilitada para todos os usuários
- **servicos**: Leitura habilitada para todos os usuários
- **agendamentos**: Acesso completo para roles autorizadas

### Permissões Granulares

Todas as funções, procedures, tabelas e sequências têm permissões explícitas configuradas para:
- `anon` (usuários não autenticados)
- `authenticated` (usuários autenticados)
- `service_role` (aplicação)

## 📦 Dependências

```json
{
  "devDependencies": {
    "supabase": "^2.105.0"
  }
}
```

## 🚀 Como Usar

### Instalação

```bash
npm install
```

### Inicializar Supabase

```bash
npx supabase start
```

### Executar Migrations

```bash
npx supabase db push
```

### Exemplo de Uso

#### Verificar Disponibilidade
```sql
SELECT fn_verificar_disponibilidade(1, 1, '2026-06-10 14:00:00');
```

#### Realizar Agendamento
```sql
SELECT proc_realiza_agendamento(1, 1, 1, '2026-06-10 14:00:00');
```

#### Consultar Agendamentos
```sql
SELECT * FROM v_agendamento WHERE status = 'PENDENTE';
```

## 📊 Triggers

### `trg_log_agendamento`
Trigger automático que dispara após INSERT, UPDATE ou DELETE na tabela `agendamentos` para registrar a operação no log.

## 🔄 Fluxo de Agendamento

1. **Cliente solicita agendamento** com serviço, profissional e horário
2. **Sistema valida disponibilidade** usando `fn_verificar_disponibilidade()`
3. **Se disponível:**
   - Insere registro em `agendamentos` com status 'PENDENTE'
   - Trigger `trg_log_agendamento` registra a operação
4. **Se indisponível:** Retorna erro de conflito


