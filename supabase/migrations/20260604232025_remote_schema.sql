SET
    statement_timeout = 0;

SET
    lock_timeout = 0;

SET
    idle_in_transaction_session_timeout = 0;

SET
    client_encoding = 'UTF8';

SET
    standard_conforming_strings = on;

SELECT
    pg_catalog.set_config ('search_path', '', false);

SET
    check_function_bodies = false;

SET
    xmloption = content;

SET
    client_min_messages = warning;

SET
    row_security = off;

COMMENT ON SCHEMA "public" IS 'standard public schema';

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements"
WITH
    SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto"
WITH
    SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "supabase_vault"
WITH
    SCHEMA "vault";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp"
WITH
    SCHEMA "extensions";

CREATE
OR REPLACE FUNCTION "public"."fn_log_agendamento" () RETURNS "trigger" LANGUAGE "plpgsql" AS $$BEGIN

    INSERT INTO log_agendamentos (
        tipo_operacao,
        data_operacao
    )
    VALUES (
        TG_OP,
        CURRENT_TIMESTAMP
    );
    RETURN NEW;
END;$$;

ALTER FUNCTION "public"."fn_log_agendamento" () OWNER TO "postgres";

CREATE
OR REPLACE FUNCTION "public"."fn_verificar_disponibilidade" (
    "p_id_profissional" integer,
    "p_id_servico" integer,
    "p_data_atendimento" timestamp without time zone
) RETURNS boolean LANGUAGE "plpgsql" AS $$
DECLARE

  v_duracao INTERVAL;
  v_data_fim TIMESTAMP;
  v_conflitos INTEGER;

BEGIN

  SELECT duracao
  INTO v_duracao
  FROM servicos
  WHERE id = p_id_servico;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Serviço % não encontrado.', p_id_servico;
  END IF;

  v_data_fim := p_data_atendimento + v_duracao;

  SELECT COUNT(*)
    INTO v_conflitos
    FROM agendamentos a
    JOIN servicos s
      ON s.id = a.id_servico
   WHERE a.id_profissional = p_id_profissional
     AND a.status <> 'CANCELADO'
     AND p_data_atendimento < (a.data_atendimento + s.duracao)
     AND v_data_fim > a.data_atendimento;

  RETURN v_conflitos = 0;

END;
$$;

ALTER FUNCTION "public"."fn_verificar_disponibilidade" (
    "p_id_profissional" integer,
    "p_id_servico" integer,
    "p_data_atendimento" timestamp without time zone
) OWNER TO "postgres";

CREATE
OR REPLACE FUNCTION "public"."proc_realiza_agendamento" (
    "p_id_servico" integer,
    "p_id_profissional" integer,
    "p_id_cliente" integer,
    "p_data_atendimento" timestamp without time zone
) RETURNS integer LANGUAGE "plpgsql" AS $$
DECLARE
    v_duracao INTERVAL;
    v_data_fim TIMESTAMP;
    v_conflito INTEGER;
    v_id_agendamento INTEGER;
BEGIN

    SELECT duracao
      INTO v_duracao
      FROM servicos
     WHERE id = p_id_servico;

    IF v_duracao IS NULL THEN
        RAISE EXCEPTION 'Serviço % não encontrado.', p_id_servico;
    END IF;

    v_data_fim := p_data_atendimento + v_duracao;

    SELECT COUNT(*)
      INTO v_conflito
      FROM agendamentos a
      JOIN servicos s
        ON s.id = a.id_servico
     WHERE a.id_profissional = p_id_profissional
       AND a.status <> 'CANCELADO'
       AND p_data_atendimento < (a.data_atendimento + s.duracao)
       AND v_data_fim > a.data_atendimento;

    IF v_conflito > 0 THEN
        RAISE EXCEPTION
            'Já existe um atendimento agendado para este profissional neste horário.';
    END IF;

    INSERT INTO agendamentos (
        id_servico,
        id_profissional,
        id_cliente,
        data_atendimento,
        status
    )
    VALUES (
        p_id_servico,
        p_id_profissional,
        p_id_cliente,
        p_data_atendimento,
        'PENDENTE'
    )
    RETURNING id INTO v_id_agendamento;

    RETURN v_id_agendamento;

END;
$$;

ALTER FUNCTION "public"."proc_realiza_agendamento" (
    "p_id_servico" integer,
    "p_id_profissional" integer,
    "p_id_cliente" integer,
    "p_data_atendimento" timestamp without time zone
) OWNER TO "postgres";

CREATE PROCEDURE "public"."proc_realizar_agendamento" (
    IN "p_id_servico" integer,
    IN "p_id_profissional" integer,
    IN "p_id_cliente" integer,
    IN "p_data_atendimento" timestamp without time zone
) LANGUAGE "plpgsql" AS $$
BEGIN

    IF NOT verificar_disponibilidade(
            p_id_profissional,
            p_id_servico,
            p_data_atendimento
       )
    THEN
        RAISE EXCEPTION
            'O profissional já possui atendimento neste período.';
    END IF;

    INSERT INTO agendamentos (
        id_servico,
        id_profissional,
        id_cliente,
        data_atendimento,
        status
    )
    VALUES (
        p_id_servico,
        p_id_profissional,
        p_id_cliente,
        p_data_atendimento,
        'PENDENTE'
    );

END;
$$;

ALTER PROCEDURE "public"."proc_realizar_agendamento" (
    IN "p_id_servico" integer,
    IN "p_id_profissional" integer,
    IN "p_id_cliente" integer,
    IN "p_data_atendimento" timestamp without time zone
) OWNER TO "postgres";

SET
    default_tablespace = '';

SET
    default_table_access_method = "heap";

CREATE TABLE IF NOT EXISTS
    "public"."agendamentos" (
        "id" integer NOT NULL,
        "id_servico" integer NOT NULL,
        "id_profissional" integer NOT NULL,
        "id_cliente" integer,
        "data_atendimento" timestamp without time zone NOT NULL,
        "status" "text" NOT NULL,
        CONSTRAINT "agendamentos_status_check" CHECK (
            (
                "status" = ANY (
                    ARRAY[
                        'CONCLUIDO'::"text",
                        'CANCELADO'::"text",
                        'PENDENTE'::"text"
                    ]
                )
            )
        ),
        CONSTRAINT "check_horario_retroativo" CHECK (("data_atendimento" >= CURRENT_TIMESTAMP))
    );

ALTER TABLE "public"."agendamentos" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."agendamentos_id_seq" AS integer START
WITH
    1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE "public"."agendamentos_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."agendamentos_id_seq" OWNED BY "public"."agendamentos"."id";

CREATE TABLE IF NOT EXISTS
    "public"."clientes" (
        "id" integer NOT NULL,
        "cliente" "text" NOT NULL,
        "contato" integer NOT NULL
    );

ALTER TABLE "public"."clientes" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."clientes_id_seq" AS integer START
WITH
    1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE "public"."clientes_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."clientes_id_seq" OWNED BY "public"."clientes"."id";

CREATE TABLE IF NOT EXISTS
    "public"."log_agendamentos" (
        "id" integer NOT NULL,
        "tipo_operacao" character varying(10) NOT NULL,
        "data_operacao" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
    );

ALTER TABLE "public"."log_agendamentos" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."log_agendamentos_id_seq" AS integer START
WITH
    1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE "public"."log_agendamentos_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."log_agendamentos_id_seq" OWNED BY "public"."log_agendamentos"."id";

CREATE TABLE IF NOT EXISTS
    "public"."profissionais" (
        "id" integer NOT NULL,
        "profissional" "text" NOT NULL,
        "id_servico" integer NOT NULL
    );

ALTER TABLE "public"."profissionais" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."profissionais_id_seq" AS integer START
WITH
    1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE "public"."profissionais_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."profissionais_id_seq" OWNED BY "public"."profissionais"."id";

CREATE TABLE IF NOT EXISTS
    "public"."servicos" (
        "id" integer NOT NULL,
        "descricao" "text" NOT NULL,
        "duracao" interval NOT NULL,
        "preco" numeric(10, 2) NOT NULL,
        CONSTRAINT "check_duracao_negativa" CHECK (("duracao" > '00:00:00'::interval)),
        CONSTRAINT "check_preco_negativo" CHECK (("preco" > (0)::numeric))
    );

ALTER TABLE "public"."servicos" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."servicos_id_seq" AS integer START
WITH
    1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

ALTER SEQUENCE "public"."servicos_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."servicos_id_seq" OWNED BY "public"."servicos"."id";

CREATE OR REPLACE VIEW
    "public"."v_agendamento" AS
WITH
    "tabagendamento" AS (
        SELECT
            "s"."descricao" AS "servico",
            "p"."profissional",
            "c"."cliente",
            "s"."preco" AS "valor_servico",
            "date_trunc" ('minute'::"text", "a"."data_atendimento") AS "data_atendimento",
            "s"."duracao",
            "date_trunc" (
                'minute'::"text",
                ("a"."data_atendimento" + "s"."duracao")
            ) AS "data_fim",
            "a"."status"
        FROM
            (
                (
                    (
                        "public"."agendamentos" "a"
                        JOIN "public"."servicos" "s" ON (("s"."id" = "a"."id_servico"))
                    )
                    JOIN "public"."clientes" "c" ON (("c"."id" = "a"."id_cliente"))
                )
                JOIN "public"."profissionais" "p" ON (("p"."id" = "a"."id_profissional"))
            )
    )
SELECT
    "servico",
    "profissional",
    "cliente",
    "valor_servico",
    "data_atendimento",
    "duracao",
    "data_fim",
    "status"
FROM
    "tabagendamento";

ALTER VIEW "public"."v_agendamento" OWNER TO "postgres";

ALTER TABLE ONLY "public"."agendamentos"
ALTER COLUMN "id"
SET DEFAULT "nextval" ('"public"."agendamentos_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."clientes"
ALTER COLUMN "id"
SET DEFAULT "nextval" ('"public"."clientes_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."log_agendamentos"
ALTER COLUMN "id"
SET DEFAULT "nextval" ('"public"."log_agendamentos_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."profissionais"
ALTER COLUMN "id"
SET DEFAULT "nextval" ('"public"."profissionais_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."servicos"
ALTER COLUMN "id"
SET DEFAULT "nextval" ('"public"."servicos_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."agendamentos"
ADD CONSTRAINT "agendamentos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."clientes"
ADD CONSTRAINT "clientes_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."log_agendamentos"
ADD CONSTRAINT "log_agendamentos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profissionais"
ADD CONSTRAINT "profissionais_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."servicos"
ADD CONSTRAINT "servicos_pkey" PRIMARY KEY ("id");

CREATE
OR REPLACE TRIGGER "trg_log_agendamento"
AFTER INSERT
OR DELETE
OR
UPDATE ON "public"."agendamentos" FOR EACH ROW
EXECUTE FUNCTION "public"."fn_log_agendamento" ();

ALTER TABLE ONLY "public"."agendamentos"
ADD CONSTRAINT "fk_cliente_agendamento" FOREIGN KEY ("id_cliente") REFERENCES "public"."clientes" ("id");

ALTER TABLE ONLY "public"."agendamentos"
ADD CONSTRAINT "fk_profissional_agendamento" FOREIGN KEY ("id_profissional") REFERENCES "public"."profissionais" ("id");

ALTER TABLE ONLY "public"."agendamentos"
ADD CONSTRAINT "fk_servico_agendamento" FOREIGN KEY ("id_servico") REFERENCES "public"."servicos" ("id");

ALTER TABLE ONLY "public"."profissionais"
ADD CONSTRAINT "fk_servico_profissional" FOREIGN KEY ("id_servico") REFERENCES "public"."servicos" ("id");

CREATE POLICY "Enable read access for all users" ON "public"."clientes" FOR
SELECT
    USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."profissionais" FOR
SELECT
    USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."servicos" FOR
SELECT
    USING (true);

ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";

GRANT USAGE ON SCHEMA "public" TO "postgres";

GRANT USAGE ON SCHEMA "public" TO "anon";

GRANT USAGE ON SCHEMA "public" TO "authenticated";

GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON FUNCTION "public"."fn_log_agendamento" () TO "anon";

GRANT ALL ON FUNCTION "public"."fn_log_agendamento" () TO "authenticated";

GRANT ALL ON FUNCTION "public"."fn_log_agendamento" () TO "service_role";

GRANT ALL ON FUNCTION "public"."fn_verificar_disponibilidade" (
    "p_id_profissional" integer,
    "p_id_servico" integer,
    "p_data_atendimento" timestamp without time zone
) TO "anon";

GRANT ALL ON FUNCTION "public"."fn_verificar_disponibilidade" (
    "p_id_profissional" integer,
    "p_id_servico" integer,
    "p_data_atendimento" timestamp without time zone
) TO "authenticated";

GRANT ALL ON FUNCTION "public"."fn_verificar_disponibilidade" (
    "p_id_profissional" integer,
    "p_id_servico" integer,
    "p_data_atendimento" timestamp without time zone
) TO "service_role";

GRANT ALL ON FUNCTION "public"."proc_realiza_agendamento" (
    "p_id_servico" integer,
    "p_id_profissional" integer,
    "p_id_cliente" integer,
    "p_data_atendimento" timestamp without time zone
) TO "anon";

GRANT ALL ON FUNCTION "public"."proc_realiza_agendamento" (
    "p_id_servico" integer,
    "p_id_profissional" integer,
    "p_id_cliente" integer,
    "p_data_atendimento" timestamp without time zone
) TO "authenticated";

GRANT ALL ON FUNCTION "public"."proc_realiza_agendamento" (
    "p_id_servico" integer,
    "p_id_profissional" integer,
    "p_id_cliente" integer,
    "p_data_atendimento" timestamp without time zone
) TO "service_role";

GRANT ALL ON PROCEDURE "public"."proc_realizar_agendamento" (
    IN "p_id_servico" integer,
    IN "p_id_profissional" integer,
    IN "p_id_cliente" integer,
    IN "p_data_atendimento" timestamp without time zone
) TO "anon";

GRANT ALL ON PROCEDURE "public"."proc_realizar_agendamento" (
    IN "p_id_servico" integer,
    IN "p_id_profissional" integer,
    IN "p_id_cliente" integer,
    IN "p_data_atendimento" timestamp without time zone
) TO "authenticated";

GRANT ALL ON PROCEDURE "public"."proc_realizar_agendamento" (
    IN "p_id_servico" integer,
    IN "p_id_profissional" integer,
    IN "p_id_cliente" integer,
    IN "p_data_atendimento" timestamp without time zone
) TO "service_role";

GRANT ALL ON TABLE "public"."agendamentos" TO "anon";

GRANT ALL ON TABLE "public"."agendamentos" TO "authenticated";

GRANT ALL ON TABLE "public"."agendamentos" TO "service_role";

GRANT ALL ON SEQUENCE "public"."agendamentos_id_seq" TO "anon";

GRANT ALL ON SEQUENCE "public"."agendamentos_id_seq" TO "authenticated";

GRANT ALL ON SEQUENCE "public"."agendamentos_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."clientes" TO "anon";

GRANT ALL ON TABLE "public"."clientes" TO "authenticated";

GRANT ALL ON TABLE "public"."clientes" TO "service_role";

GRANT ALL ON SEQUENCE "public"."clientes_id_seq" TO "anon";

GRANT ALL ON SEQUENCE "public"."clientes_id_seq" TO "authenticated";

GRANT ALL ON SEQUENCE "public"."clientes_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."log_agendamentos" TO "anon";

GRANT ALL ON TABLE "public"."log_agendamentos" TO "authenticated";

GRANT ALL ON TABLE "public"."log_agendamentos" TO "service_role";

GRANT ALL ON SEQUENCE "public"."log_agendamentos_id_seq" TO "anon";

GRANT ALL ON SEQUENCE "public"."log_agendamentos_id_seq" TO "authenticated";

GRANT ALL ON SEQUENCE "public"."log_agendamentos_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."profissionais" TO "anon";

GRANT ALL ON TABLE "public"."profissionais" TO "authenticated";

GRANT ALL ON TABLE "public"."profissionais" TO "service_role";

GRANT ALL ON SEQUENCE "public"."profissionais_id_seq" TO "anon";

GRANT ALL ON SEQUENCE "public"."profissionais_id_seq" TO "authenticated";

GRANT ALL ON SEQUENCE "public"."profissionais_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."servicos" TO "anon";

GRANT ALL ON TABLE "public"."servicos" TO "authenticated";

GRANT ALL ON TABLE "public"."servicos" TO "service_role";

GRANT ALL ON SEQUENCE "public"."servicos_id_seq" TO "anon";

GRANT ALL ON SEQUENCE "public"."servicos_id_seq" TO "authenticated";

GRANT ALL ON SEQUENCE "public"."servicos_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."v_agendamento" TO "anon";

GRANT ALL ON TABLE "public"."v_agendamento" TO "authenticated";

GRANT ALL ON TABLE "public"."v_agendamento" TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON SEQUENCES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON SEQUENCES TO "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON SEQUENCES TO "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON SEQUENCES TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON FUNCTIONS TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON FUNCTIONS TO "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON FUNCTIONS TO "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON FUNCTIONS TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON TABLES TO "postgres";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON TABLES TO "anon";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON TABLES TO "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
GRANT ALL ON TABLES TO "service_role";

drop extension if exists "pg_net";