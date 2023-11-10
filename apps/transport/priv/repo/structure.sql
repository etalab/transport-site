--
-- PostgreSQL database dump
--

-- Dumped from database version 15.4 (Debian 15.4-2.pgdg110+1)
-- Dumped by pg_dump version 16.0 (Debian 16.0-1.pgdg110+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgis_topology; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA postgis_topology;


--
-- Name: tiger; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tiger;


--
-- Name: tiger_data; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tiger_data;


--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA topology;


--
-- Name: SCHEMA topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA topology IS 'PostGIS Topology schema';


--
-- Name: adminpack; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS adminpack WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION adminpack; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION adminpack IS 'administrative functions for PostgreSQL';


--
-- Name: autoinc; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS autoinc WITH SCHEMA public;


--
-- Name: EXTENSION autoinc; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION autoinc IS 'functions for autoincrementing fields';


--
-- Name: btree_gin; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gin WITH SCHEMA public;


--
-- Name: EXTENSION btree_gin; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gin IS 'support for indexing common datatypes in GIN';


--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: cube; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS cube WITH SCHEMA public;


--
-- Name: EXTENSION cube; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION cube IS 'data type for multidimensional cubes';


--
-- Name: dblink; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA public;


--
-- Name: EXTENSION dblink; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION dblink IS 'connect to other PostgreSQL databases from within a database';


--
-- Name: dict_int; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS dict_int WITH SCHEMA public;


--
-- Name: EXTENSION dict_int; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION dict_int IS 'text search dictionary template for integers';


--
-- Name: dict_xsyn; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS dict_xsyn WITH SCHEMA public;


--
-- Name: EXTENSION dict_xsyn; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION dict_xsyn IS 'text search dictionary template for extended synonym processing';


--
-- Name: earthdistance; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS earthdistance WITH SCHEMA public;


--
-- Name: EXTENSION earthdistance; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION earthdistance IS 'calculate great-circle distances on the surface of the Earth';


--
-- Name: file_fdw; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS file_fdw WITH SCHEMA public;


--
-- Name: EXTENSION file_fdw; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION file_fdw IS 'foreign-data wrapper for flat file access';


--
-- Name: fuzzystrmatch; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA public;


--
-- Name: EXTENSION fuzzystrmatch; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION fuzzystrmatch IS 'determine similarities and distance between strings';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: insert_username; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS insert_username WITH SCHEMA public;


--
-- Name: EXTENSION insert_username; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION insert_username IS 'functions for tracking who changed a table';


--
-- Name: intagg; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS intagg WITH SCHEMA public;


--
-- Name: EXTENSION intagg; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION intagg IS 'integer aggregator and enumerator (obsolete)';


--
-- Name: intarray; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS intarray WITH SCHEMA public;


--
-- Name: EXTENSION intarray; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION intarray IS 'functions, operators, and index support for 1-D arrays of integers';


--
-- Name: isn; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS isn WITH SCHEMA public;


--
-- Name: EXTENSION isn; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION isn IS 'data types for international product numbering standards';


--
-- Name: lo; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS lo WITH SCHEMA public;


--
-- Name: EXTENSION lo; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION lo IS 'Large Object maintenance';


--
-- Name: ltree; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS ltree WITH SCHEMA public;


--
-- Name: EXTENSION ltree; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION ltree IS 'data type for hierarchical tree-like structures';


--
-- Name: moddatetime; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS moddatetime WITH SCHEMA public;


--
-- Name: EXTENSION moddatetime; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION moddatetime IS 'functions for tracking last modification time';


--
-- Name: pageinspect; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pageinspect WITH SCHEMA public;


--
-- Name: EXTENSION pageinspect; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pageinspect IS 'inspect the contents of database pages at a low level';


--
-- Name: pg_buffercache; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_buffercache WITH SCHEMA public;


--
-- Name: EXTENSION pg_buffercache; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_buffercache IS 'examine the shared buffer cache';


--
-- Name: pg_freespacemap; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_freespacemap WITH SCHEMA public;


--
-- Name: EXTENSION pg_freespacemap; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_freespacemap IS 'examine the free space map (FSM)';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track execution statistics of all SQL statements executed';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: pgrowlocks; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgrowlocks WITH SCHEMA public;


--
-- Name: EXTENSION pgrowlocks; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgrowlocks IS 'show row-level locking information';


--
-- Name: pgstattuple; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgstattuple WITH SCHEMA public;


--
-- Name: EXTENSION pgstattuple; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgstattuple IS 'show tuple-level statistics';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- Name: postgis_raster; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;


--
-- Name: EXTENSION postgis_raster; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_raster IS 'PostGIS raster types and functions';


--
-- Name: postgis_tiger_geocoder; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder WITH SCHEMA tiger;


--
-- Name: EXTENSION postgis_tiger_geocoder; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_tiger_geocoder IS 'PostGIS tiger geocoder and reverse geocoder';


--
-- Name: postgis_topology; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;


--
-- Name: EXTENSION postgis_topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_topology IS 'PostGIS topology spatial types and functions';


--
-- Name: postgres_fdw; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgres_fdw WITH SCHEMA public;


--
-- Name: EXTENSION postgres_fdw; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgres_fdw IS 'foreign-data wrapper for remote PostgreSQL servers';


--
-- Name: refint; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS refint WITH SCHEMA public;


--
-- Name: EXTENSION refint; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION refint IS 'functions for implementing referential integrity (obsolete)';


--
-- Name: seg; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS seg WITH SCHEMA public;


--
-- Name: EXTENSION seg; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION seg IS 'data type for representing line segments or floating-point intervals';


--
-- Name: sslinfo; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS sslinfo WITH SCHEMA public;


--
-- Name: EXTENSION sslinfo; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION sslinfo IS 'information about SSL certificates';


--
-- Name: tablefunc; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS tablefunc WITH SCHEMA public;


--
-- Name: EXTENSION tablefunc; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION tablefunc IS 'functions that manipulate whole tables, including crosstab';


--
-- Name: tcn; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS tcn WITH SCHEMA public;


--
-- Name: EXTENSION tcn; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION tcn IS 'Triggered change notifications';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: xml2; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS xml2 WITH SCHEMA public;


--
-- Name: EXTENSION xml2; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION xml2 IS 'XPath querying and XSLT';


--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


--
-- Name: aom_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.aom_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
    dataset_id dataset.id%TYPE;
  BEGIN
  SELECT dataset.id INTO dataset_id FROM dataset WHERE aom_id = NEW.id;

  IF dataset_id IS NOT NULL THEN
    UPDATE dataset SET id = id WHERE id = dataset_id;
  END IF;

  RETURN NEW;
  END
  $$;


--
-- Name: dataset_communes_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.dataset_communes_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

IF NEW.dataset_id IS NOT NULL THEN
UPDATE dataset SET id = id WHERE id = NEW.dataset_id;
END IF;

RETURN NEW;
END
$$;


--
-- Name: dataset_search_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.dataset_search_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
nom text;
region_nom region.nom%TYPE;
population dataset.population%TYPE;
BEGIN

NEW.search_vector = setweight(to_tsvector('custom_french', coalesce(NEW.custom_title, '')), 'B') ||
setweight(to_tsvector('custom_french', array_to_string(NEW.tags, ',')), 'C') ||
setweight(to_tsvector('custom_french', coalesce(NEW.description, '')), 'D');

IF NEW.aom_id IS NOT NULL THEN
SELECT aom.nom, region.nom, aom.population INTO nom, region_nom, population
FROM aom
JOIN region ON region.id = aom.region_id
WHERE aom.id = NEW.aom_id;

NEW.search_vector = NEW.search_vector ||
setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A') ||
setweight(to_tsvector('custom_french', coalesce(region_nom, '')), 'B');
NEW.population = population;

SELECT string_agg(commune.nom, ' ') INTO nom
FROM commune
JOIN aom ON aom.composition_res_id = commune.aom_res_id
WHERE aom.id = NEW.aom_id;

NEW.search_vector = NEW.search_vector ||
setweight(to_tsvector('custom_french', coalesce(nom, '')), 'B');

ELSIF NEW.region_id IS NOT NULL THEN
SELECT region.nom, SUM(aom.population) INTO nom, population
FROM region
JOIN aom ON aom.region_id = region.id
WHERE region.id = NEW.region_id
GROUP BY region.nom;

NEW.search_vector = NEW.search_vector ||
setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
NEW.population = population;

ELSE
SELECT coalesce(sum(c.population),0) INTO population FROM dataset_communes dc
LEFT JOIN commune c ON c.id = dc.commune_id WHERE dc.dataset_id = NEW.id;

NEW.population = population;
END IF;

IF EXISTS (
  select dataset_id
  from dataset_aom_legal_owner
  where dataset_id = NEW.id
  group by dataset_id
  having count(aom_id) >= 2
) THEN
SELECT string_agg(a.nom, ' ') INTO nom
from aom a
left join dataset_aom_legal_owner d on d.aom_id = a.id
where d.dataset_id = NEW.id OR a.id = NEW.aom_id;

NEW.search_vector = NEW.search_vector ||
setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
END IF;

RETURN NEW;
END
$$;


--
-- Name: oban_jobs_notify(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.oban_jobs_notify() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  channel text;
  notice json;
BEGIN
  IF NEW.state = 'available' THEN
    channel = 'public.oban_insert';
    notice = json_build_object('queue', NEW.queue);

    PERFORM pg_notify(channel, notice::text);
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: refresh_dataset_geographic_view(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_dataset_geographic_view() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW dataset_geographic_view;
    RETURN NULL;
  END;
  $$;


--
-- Name: refresh_places(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_places() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  REFRESH MATERIALIZED VIEW places;
  RETURN NULL;
END;
$$;


--
-- Name: region_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.region_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE
    dataset_id dataset.id%TYPE;
  BEGIN
  SELECT dataset.id INTO dataset_id FROM dataset WHERE region_id = NEW.id;

  IF dataset_id IS NOT NULL THEN
    UPDATE dataset SET id = id WHERE id = dataset_id;
  END IF;

  RETURN NEW;
  END
  $$;


--
-- Name: custom_french; Type: TEXT SEARCH CONFIGURATION; Schema: public; Owner: -
--

CREATE TEXT SEARCH CONFIGURATION public.custom_french (
    PARSER = pg_catalog."default" );

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR asciiword WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR word WITH public.unaccent, simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR numword WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR email WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR url WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR host WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR sfloat WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR version WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR hword_numpart WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR hword_part WITH public.unaccent, simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR hword_asciipart WITH public.unaccent, simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR numhword WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR asciihword WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR hword WITH public.unaccent, simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR url_path WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR file WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR "float" WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR "int" WITH simple;

ALTER TEXT SEARCH CONFIGURATION public.custom_french
    ADD MAPPING FOR uint WITH simple;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: aom; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aom (
    id bigint NOT NULL,
    composition_res_id integer,
    insee_commune_principale character varying(255),
    region_name character varying(255),
    departement character varying(255),
    siren character varying(255),
    nom character varying(255),
    forme_juridique character varying(255),
    nombre_communes integer,
    population integer,
    surface character varying(255),
    region_id bigint,
    geom public.geometry
);


--
-- Name: aom_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.aom_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: aom_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.aom_id_seq OWNED BY public.aom.id;


--
-- Name: breaking_news; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.breaking_news (
    id bigint NOT NULL,
    level character varying(255),
    msg character varying(255)
);


--
-- Name: breaking_news_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.breaking_news_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: breaking_news_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.breaking_news_id_seq OWNED BY public.breaking_news.id;


--
-- Name: commune; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commune (
    id bigint NOT NULL,
    insee character varying(255),
    nom character varying(255),
    surf_ha double precision,
    geom public.geometry,
    aom_res_id bigint,
    region_id bigint,
    siren character varying(255),
    population integer,
    arrondissement_insee character varying(255),
    departement_insee character varying(255)
);


--
-- Name: commune_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.commune_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: commune_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.commune_id_seq OWNED BY public.commune.id;


--
-- Name: contact; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact (
    id bigint NOT NULL,
    first_name character varying(255),
    last_name character varying(255),
    organization character varying(255) NOT NULL,
    job_title character varying(255),
    email bytea NOT NULL,
    email_hash bytea NOT NULL,
    phone_number bytea,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    mailing_list_title character varying(255),
    secondary_phone_number bytea,
    datagouv_user_id character varying(255),
    last_login_at timestamp without time zone
);


--
-- Name: contact_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contact_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contact_id_seq OWNED BY public.contact.id;


--
-- Name: contacts_organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts_organizations (
    contact_id bigint NOT NULL,
    organization_id character varying(255) NOT NULL
);


--
-- Name: data_conversion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_conversion (
    id bigint NOT NULL,
    convert_from character varying(255) NOT NULL,
    convert_to character varying(255) NOT NULL,
    resource_history_uuid uuid NOT NULL,
    payload jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    status character varying NOT NULL,
    converter character varying NOT NULL,
    converter_version character varying NOT NULL,
    CONSTRAINT allowed_from_formats CHECK (((convert_from)::text = 'GTFS'::text)),
    CONSTRAINT allowed_to_formats CHECK (((convert_to)::text = ANY (ARRAY[('GeoJSON'::character varying)::text, ('NeTEx'::character varying)::text])))
);


--
-- Name: data_conversion_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.data_conversion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: data_conversion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.data_conversion_id_seq OWNED BY public.data_conversion.id;


--
-- Name: data_import; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_import (
    id bigint NOT NULL,
    resource_history_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: data_import_batch; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_import_batch (
    id bigint NOT NULL,
    summary jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: data_import_batch_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.data_import_batch_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: data_import_batch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.data_import_batch_id_seq OWNED BY public.data_import_batch.id;


--
-- Name: data_import_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.data_import_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: data_import_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.data_import_id_seq OWNED BY public.data_import.id;


--
-- Name: dataset; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset (
    id bigint NOT NULL,
    datagouv_id character varying(255),
    custom_title character varying(255),
    created_at timestamp without time zone NOT NULL,
    description text,
    frequency character varying(255),
    last_update timestamp without time zone NOT NULL,
    licence character varying(255),
    logo character varying(255),
    full_logo character varying(255),
    slug character varying(255),
    tags character varying(255)[],
    datagouv_title character varying(255),
    type character varying(255),
    region_id bigint,
    aom_id bigint,
    organization character varying(255),
    has_realtime boolean DEFAULT false,
    is_active boolean DEFAULT true,
    search_vector tsvector,
    population integer,
    nb_reuses integer,
    associated_territory_name character varying(255),
    latest_data_gouv_comment_timestamp timestamp without time zone,
    inserted_at timestamp without time zone,
    updated_at timestamp without time zone,
    archived_at timestamp without time zone,
    custom_tags character varying(255)[],
    organization_type character varying(255),
    legal_owner_company_siren character varying(9),
    organization_id character varying(255)
);


--
-- Name: dataset_aom_legal_owner; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset_aom_legal_owner (
    dataset_id bigint NOT NULL,
    aom_id bigint NOT NULL
);


--
-- Name: dataset_communes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset_communes (
    dataset_id bigint,
    commune_id bigint
);


--
-- Name: region; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.region (
    id bigint NOT NULL,
    nom character varying(255),
    insee character varying(255),
    is_completed boolean,
    geom public.geometry
);


--
-- Name: dataset_geographic_view; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.dataset_geographic_view AS
 SELECT dataset.id AS dataset_id,
    COALESCE(dataset.region_id, ( SELECT aom.region_id
           FROM public.aom
          WHERE (aom.id = dataset.aom_id)), ( SELECT c.region_id
           FROM (public.dataset_communes dc
             LEFT JOIN public.commune c ON ((dc.commune_id = c.id)))
          WHERE (dc.dataset_id = dataset.id)
          ORDER BY c.aom_res_id DESC
         LIMIT 1)) AS region_id,
    COALESCE(( SELECT aom.geom
           FROM public.aom
          WHERE (aom.id = dataset.aom_id)), ( SELECT region.geom
           FROM public.region
          WHERE (region.id = dataset.region_id)), ( SELECT public.st_union(commune.geom) AS st_union
           FROM (public.commune
             LEFT JOIN public.dataset_communes ON ((commune.id = dataset_communes.commune_id)))
          WHERE (dataset_communes.dataset_id = dataset.id))) AS geom
   FROM public.dataset
  WITH NO DATA;


--
-- Name: dataset_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset_history (
    id bigint NOT NULL,
    dataset_id bigint,
    dataset_datagouv_id text,
    payload jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: dataset_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dataset_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dataset_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dataset_history_id_seq OWNED BY public.dataset_history.id;


--
-- Name: dataset_history_resources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset_history_resources (
    id bigint NOT NULL,
    dataset_history_id bigint,
    resource_id bigint,
    resource_history_id bigint,
    resource_history_last_up_to_date_at timestamp without time zone,
    resource_metadata_id bigint,
    validation_id bigint,
    payload jsonb
);


--
-- Name: dataset_history_resources_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dataset_history_resources_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dataset_history_resources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dataset_history_resources_id_seq OWNED BY public.dataset_history_resources.id;


--
-- Name: dataset_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dataset_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dataset_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dataset_id_seq OWNED BY public.dataset.id;


--
-- Name: dataset_region_legal_owner; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset_region_legal_owner (
    dataset_id bigint NOT NULL,
    region_id bigint NOT NULL
);


--
-- Name: dataset_score; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dataset_score (
    id bigint NOT NULL,
    dataset_id bigint,
    topic character varying(255),
    score double precision,
    "timestamp" timestamp without time zone,
    details jsonb
);


--
-- Name: dataset_score_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.dataset_score_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: dataset_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.dataset_score_id_seq OWNED BY public.dataset_score.id;


--
-- Name: departement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departement (
    id bigint NOT NULL,
    insee character varying(255) NOT NULL,
    region_insee character varying(255),
    chef_lieu character varying(255),
    nom character varying(255) NOT NULL,
    zone character varying(255) NOT NULL,
    geom public.geometry NOT NULL
);


--
-- Name: departement_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departement_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departement_id_seq OWNED BY public.departement.id;


--
-- Name: epci; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.epci (
    id bigint NOT NULL,
    code character varying(255),
    nom character varying(255),
    communes_insee character varying(255)[]
);


--
-- Name: epci_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.epci_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: epci_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.epci_id_seq OWNED BY public.epci.id;


--
-- Name: geo_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geo_data (
    id bigint NOT NULL,
    geom public.geometry,
    payload jsonb,
    geo_data_import_id bigint
);


--
-- Name: geo_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.geo_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: geo_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.geo_data_id_seq OWNED BY public.geo_data.id;


--
-- Name: geo_data_import; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geo_data_import (
    id bigint NOT NULL,
    resource_history_id bigint,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: geo_data_import_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.geo_data_import_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: geo_data_import_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.geo_data_import_id_seq OWNED BY public.geo_data_import.id;


--
-- Name: gtfs_calendar; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gtfs_calendar (
    id bigint NOT NULL,
    data_import_id bigint,
    service_id bytea,
    monday integer,
    tuesday integer,
    wednesday integer,
    thursday integer,
    friday integer,
    saturday integer,
    sunday integer,
    days integer[],
    start_date date,
    end_date date
);


--
-- Name: gtfs_calendar_dates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gtfs_calendar_dates (
    id bigint NOT NULL,
    data_import_id bigint,
    service_id bytea,
    date date,
    exception_type integer
);


--
-- Name: gtfs_calendar_dates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gtfs_calendar_dates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gtfs_calendar_dates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gtfs_calendar_dates_id_seq OWNED BY public.gtfs_calendar_dates.id;


--
-- Name: gtfs_calendar_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gtfs_calendar_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gtfs_calendar_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gtfs_calendar_id_seq OWNED BY public.gtfs_calendar.id;


--
-- Name: gtfs_stop_times; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gtfs_stop_times (
    id bigint NOT NULL,
    data_import_id bigint,
    trip_id bytea,
    stop_id bytea,
    stop_sequence integer,
    arrival_time interval hour to second,
    departure_time interval hour to second
);


--
-- Name: gtfs_stop_times_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gtfs_stop_times_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gtfs_stop_times_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gtfs_stop_times_id_seq OWNED BY public.gtfs_stop_times.id;


--
-- Name: gtfs_stops; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gtfs_stops (
    id bigint NOT NULL,
    data_import_id bigint,
    stop_id bytea,
    stop_name bytea,
    stop_lat double precision,
    stop_lon double precision,
    location_type integer
);


--
-- Name: gtfs_stops_clusters_level_1; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_1 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (3.5)::double precision, (2.0)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (3.5)::double precision, (2.0)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_10; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_10 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.006866455078125002)::double precision, (0.004737390745495734)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.006866455078125002)::double precision, (0.004737390745495734)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_11; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_11 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.0034332275390624983)::double precision, (0.002259008904275428)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.0034332275390624983)::double precision, (0.002259008904275428)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_12; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_12 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.00171661376953125)::double precision, (0.0011294445140095472)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.00171661376953125)::double precision, (0.0011294445140095472)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_2; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_2 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (1.7578125000000004)::double precision, (1.189324575526938)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (1.7578125000000004)::double precision, (1.189324575526938)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_3; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_3 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.8789062500000002)::double precision, (0.6065068377804875)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.8789062500000002)::double precision, (0.6065068377804875)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_4; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_4 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.4394531250000001)::double precision, (0.3034851814036069)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.4394531250000001)::double precision, (0.3034851814036069)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_5; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_5 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.21972656250000006)::double precision, (0.15165412371973086)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.21972656250000006)::double precision, (0.15165412371973086)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_6; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_6 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.10986328125000003)::double precision, (0.07580875200863536)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.10986328125000003)::double precision, (0.07580875200863536)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_7; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_7 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.054931640625000014)::double precision, (0.037900705683396894)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.054931640625000014)::double precision, (0.037900705683396894)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_8; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_8 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.027465820312500007)::double precision, (0.018949562981982936)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.027465820312500007)::double precision, (0.018949562981982936)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_clusters_level_9; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.gtfs_stops_clusters_level_9 AS
 SELECT public.st_x(public.st_transform(s0.cluster, 4326)) AS cluster_lon,
    public.st_y(public.st_transform(s0.cluster, 4326)) AS cluster_lat,
    s0.count
   FROM ( SELECT public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.013732910156250003)::double precision, (0.009474781490991468)::double precision) AS cluster,
            count(*) AS count
           FROM public.gtfs_stops sg0
          WHERE ((sg0.stop_lon >= ('-100.291948'::numeric)::double precision) AND (sg0.stop_lon <= (166.6637328)::double precision) AND ((sg0.stop_lat >= ('-22.3081'::numeric)::double precision) AND (sg0.stop_lat <= (60.676445)::double precision)))
          GROUP BY (public.st_snaptogrid(public.st_setsrid(public.st_makepoint(sg0.stop_lon, sg0.stop_lat), 4326), (0.013732910156250003)::double precision, (0.009474781490991468)::double precision))) s0
  WHERE (s0.count > 0)
  WITH NO DATA;


--
-- Name: gtfs_stops_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gtfs_stops_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gtfs_stops_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gtfs_stops_id_seq OWNED BY public.gtfs_stops.id;


--
-- Name: gtfs_trips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gtfs_trips (
    id bigint NOT NULL,
    data_import_id bigint,
    route_id bytea,
    service_id bytea,
    trip_id bytea
);


--
-- Name: gtfs_trips_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.gtfs_trips_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: gtfs_trips_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.gtfs_trips_id_seq OWNED BY public.gtfs_trips.id;


--
-- Name: logs_import; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.logs_import (
    id bigint NOT NULL,
    dataset_id bigint,
    datagouv_id character varying(255),
    "timestamp" timestamp(0) without time zone,
    is_success boolean,
    error_msg text
);


--
-- Name: logs_import_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.logs_import_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: logs_import_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.logs_import_id_seq OWNED BY public.logs_import.id;


--
-- Name: metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics (
    id bigint NOT NULL,
    target character varying(255) NOT NULL,
    event character varying(255) NOT NULL,
    period timestamp without time zone NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metrics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metrics_id_seq OWNED BY public.metrics.id;


--
-- Name: multi_validation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.multi_validation (
    id bigint NOT NULL,
    validation_timestamp timestamp without time zone NOT NULL,
    validator text NOT NULL,
    validator_version text,
    command text,
    result jsonb,
    data_vis jsonb,
    resource_id bigint,
    resource_history_id bigint,
    validated_data_name text,
    secondary_resource_id bigint,
    secondary_resource_history_id bigint,
    secondary_validated_data_name text,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    oban_args jsonb,
    max_error text
);


--
-- Name: multi_validation_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.multi_validation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: multi_validation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.multi_validation_id_seq OWNED BY public.multi_validation.id;


--
-- Name: notification_subscription; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_subscription (
    id bigint NOT NULL,
    contact_id bigint NOT NULL,
    dataset_id bigint,
    reason character varying(255) NOT NULL,
    source character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    role character varying NOT NULL
);


--
-- Name: notification_subscription_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_subscription_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_subscription_id_seq OWNED BY public.notification_subscription.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    reason character varying(255) NOT NULL,
    dataset_id bigint,
    email bytea NOT NULL,
    email_hash bytea NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    dataset_datagouv_id character varying(255)
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags character varying(255)[] DEFAULT ARRAY[]::character varying[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT priority_range CHECK (((priority >= 0) AND (priority <= 3))),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.oban_jobs IS '11';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: organization; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization (
    id character varying(255) NOT NULL,
    slug character varying(255),
    name character varying(255),
    acronym character varying(255),
    logo character varying(255),
    logo_thumbnail character varying(255),
    badges jsonb[],
    metrics jsonb,
    created_at timestamp without time zone
);


--
-- Name: resource_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resource_metadata (
    id bigint NOT NULL,
    resource_id bigint,
    resource_history_id bigint,
    multi_validation_id bigint,
    metadata jsonb,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    features character varying(255)[] DEFAULT ARRAY[]::character varying[],
    modes character varying(255)[] DEFAULT ARRAY[]::character varying[]
);


--
-- Name: places; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.places AS
 SELECT place.nom,
    place.place_id,
    place.type,
    place.indexed_name
   FROM ( SELECT c.nom,
            c.insee AS place_id,
            'commune'::text AS type,
            public.unaccent(replace((c.nom)::text, ' '::text, '-'::text)) AS indexed_name
           FROM public.commune c
        UNION
         SELECT r.nom,
            (r.id)::character varying AS place_id,
            'region'::text AS type,
            public.unaccent(replace((r.nom)::text, ' '::text, '-'::text)) AS indexed_name
           FROM public.region r
        UNION
         SELECT a.nom,
            (a.id)::character varying AS place_id,
            'aom'::text AS type,
            public.unaccent(replace((a.nom)::text, ' '::text, '-'::text)) AS indexed_name
           FROM public.aom a
        UNION
         SELECT features.features AS nom,
            features.features AS place_id,
            'feature'::text AS type,
            public.unaccent(replace((features.features)::text, ' '::text, '-'::text)) AS indexed_name
           FROM ( SELECT DISTINCT unnest(resource_metadata.features) AS features
                   FROM public.resource_metadata) features
        UNION
         SELECT modes.modes AS nom,
            modes.modes AS place_id,
            'mode'::text AS type,
            public.unaccent(replace((modes.modes)::text, ' '::text, '-'::text)) AS indexed_name
           FROM ( SELECT DISTINCT unnest(resource_metadata.modes) AS modes
                   FROM public.resource_metadata) modes) place
  WITH NO DATA;


--
-- Name: region_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.region_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: region_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.region_id_seq OWNED BY public.region.id;


--
-- Name: resource; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resource (
    id bigint NOT NULL,
    url character varying(255),
    dataset_id bigint,
    format character varying(255),
    last_import timestamp without time zone NOT NULL,
    title character varying(255),
    last_update timestamp without time zone NOT NULL,
    latest_url character varying(255),
    is_available boolean DEFAULT true,
    is_community_resource boolean,
    description text,
    community_resource_publisher character varying(255),
    filesize integer,
    original_resource_url character varying(255),
    datagouv_id character varying(255),
    schema_name character varying(255),
    schema_version character varying(255),
    filetype character varying(255),
    type character varying(255),
    display_position integer
);


--
-- Name: resource_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resource_history (
    id bigint NOT NULL,
    datagouv_id character varying(255) NOT NULL,
    payload jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    last_up_to_date_at timestamp without time zone,
    resource_id bigint
);


--
-- Name: resource_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.resource_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: resource_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.resource_history_id_seq OWNED BY public.resource_history.id;


--
-- Name: resource_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.resource_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: resource_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.resource_id_seq OWNED BY public.resource.id;


--
-- Name: resource_metadata_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.resource_metadata_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: resource_metadata_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.resource_metadata_id_seq OWNED BY public.resource_metadata.id;


--
-- Name: resource_related; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resource_related (
    resource_src_id bigint NOT NULL,
    resource_dst_id bigint NOT NULL,
    reason character varying(255) NOT NULL
);


--
-- Name: resource_unavailability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resource_unavailability (
    id bigint NOT NULL,
    resource_id bigint NOT NULL,
    start timestamp(0) without time zone NOT NULL,
    "end" timestamp(0) without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: resource_unavailability_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.resource_unavailability_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: resource_unavailability_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.resource_unavailability_id_seq OWNED BY public.resource_unavailability.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: stats_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stats_history (
    id bigint NOT NULL,
    "timestamp" timestamp(0) without time zone,
    metric character varying(255),
    value numeric
);


--
-- Name: stats_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stats_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stats_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stats_history_id_seq OWNED BY public.stats_history.id;


--
-- Name: aom id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aom ALTER COLUMN id SET DEFAULT nextval('public.aom_id_seq'::regclass);


--
-- Name: breaking_news id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.breaking_news ALTER COLUMN id SET DEFAULT nextval('public.breaking_news_id_seq'::regclass);


--
-- Name: commune id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commune ALTER COLUMN id SET DEFAULT nextval('public.commune_id_seq'::regclass);


--
-- Name: contact id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact ALTER COLUMN id SET DEFAULT nextval('public.contact_id_seq'::regclass);


--
-- Name: data_conversion id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_conversion ALTER COLUMN id SET DEFAULT nextval('public.data_conversion_id_seq'::regclass);


--
-- Name: data_import id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_import ALTER COLUMN id SET DEFAULT nextval('public.data_import_id_seq'::regclass);


--
-- Name: data_import_batch id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_import_batch ALTER COLUMN id SET DEFAULT nextval('public.data_import_batch_id_seq'::regclass);


--
-- Name: dataset id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset ALTER COLUMN id SET DEFAULT nextval('public.dataset_id_seq'::regclass);


--
-- Name: dataset_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history ALTER COLUMN id SET DEFAULT nextval('public.dataset_history_id_seq'::regclass);


--
-- Name: dataset_history_resources id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history_resources ALTER COLUMN id SET DEFAULT nextval('public.dataset_history_resources_id_seq'::regclass);


--
-- Name: dataset_score id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_score ALTER COLUMN id SET DEFAULT nextval('public.dataset_score_id_seq'::regclass);


--
-- Name: departement id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departement ALTER COLUMN id SET DEFAULT nextval('public.departement_id_seq'::regclass);


--
-- Name: epci id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.epci ALTER COLUMN id SET DEFAULT nextval('public.epci_id_seq'::regclass);


--
-- Name: geo_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geo_data ALTER COLUMN id SET DEFAULT nextval('public.geo_data_id_seq'::regclass);


--
-- Name: geo_data_import id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geo_data_import ALTER COLUMN id SET DEFAULT nextval('public.geo_data_import_id_seq'::regclass);


--
-- Name: gtfs_calendar id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_calendar ALTER COLUMN id SET DEFAULT nextval('public.gtfs_calendar_id_seq'::regclass);


--
-- Name: gtfs_calendar_dates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_calendar_dates ALTER COLUMN id SET DEFAULT nextval('public.gtfs_calendar_dates_id_seq'::regclass);


--
-- Name: gtfs_stop_times id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_stop_times ALTER COLUMN id SET DEFAULT nextval('public.gtfs_stop_times_id_seq'::regclass);


--
-- Name: gtfs_stops id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_stops ALTER COLUMN id SET DEFAULT nextval('public.gtfs_stops_id_seq'::regclass);


--
-- Name: gtfs_trips id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_trips ALTER COLUMN id SET DEFAULT nextval('public.gtfs_trips_id_seq'::regclass);


--
-- Name: logs_import id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs_import ALTER COLUMN id SET DEFAULT nextval('public.logs_import_id_seq'::regclass);


--
-- Name: metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics ALTER COLUMN id SET DEFAULT nextval('public.metrics_id_seq'::regclass);


--
-- Name: multi_validation id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.multi_validation ALTER COLUMN id SET DEFAULT nextval('public.multi_validation_id_seq'::regclass);


--
-- Name: notification_subscription id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_subscription ALTER COLUMN id SET DEFAULT nextval('public.notification_subscription_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


--
-- Name: region id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.region ALTER COLUMN id SET DEFAULT nextval('public.region_id_seq'::regclass);


--
-- Name: resource id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource ALTER COLUMN id SET DEFAULT nextval('public.resource_id_seq'::regclass);


--
-- Name: resource_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_history ALTER COLUMN id SET DEFAULT nextval('public.resource_history_id_seq'::regclass);


--
-- Name: resource_metadata id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_metadata ALTER COLUMN id SET DEFAULT nextval('public.resource_metadata_id_seq'::regclass);


--
-- Name: resource_unavailability id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_unavailability ALTER COLUMN id SET DEFAULT nextval('public.resource_unavailability_id_seq'::regclass);


--
-- Name: stats_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stats_history ALTER COLUMN id SET DEFAULT nextval('public.stats_history_id_seq'::regclass);


--
-- Name: aom aom_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aom
    ADD CONSTRAINT aom_pkey PRIMARY KEY (id);


--
-- Name: breaking_news breaking_news_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.breaking_news
    ADD CONSTRAINT breaking_news_pkey PRIMARY KEY (id);


--
-- Name: commune commune_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commune
    ADD CONSTRAINT commune_pkey PRIMARY KEY (id);


--
-- Name: contact contact_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact
    ADD CONSTRAINT contact_pkey PRIMARY KEY (id);


--
-- Name: data_conversion data_conversion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_conversion
    ADD CONSTRAINT data_conversion_pkey PRIMARY KEY (id);


--
-- Name: data_import_batch data_import_batch_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_import_batch
    ADD CONSTRAINT data_import_batch_pkey PRIMARY KEY (id);


--
-- Name: data_import data_import_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_import
    ADD CONSTRAINT data_import_pkey PRIMARY KEY (id);


--
-- Name: dataset_history dataset_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history
    ADD CONSTRAINT dataset_history_pkey PRIMARY KEY (id);


--
-- Name: dataset_history_resources dataset_history_resources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history_resources
    ADD CONSTRAINT dataset_history_resources_pkey PRIMARY KEY (id);


--
-- Name: dataset dataset_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset
    ADD CONSTRAINT dataset_pkey PRIMARY KEY (id);


--
-- Name: dataset_score dataset_score_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_score
    ADD CONSTRAINT dataset_score_pkey PRIMARY KEY (id);


--
-- Name: departement departement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departement
    ADD CONSTRAINT departement_pkey PRIMARY KEY (id);


--
-- Name: epci epci_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.epci
    ADD CONSTRAINT epci_pkey PRIMARY KEY (id);


--
-- Name: geo_data_import geo_data_import_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geo_data_import
    ADD CONSTRAINT geo_data_import_pkey PRIMARY KEY (id);


--
-- Name: geo_data geo_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geo_data
    ADD CONSTRAINT geo_data_pkey PRIMARY KEY (id);


--
-- Name: gtfs_calendar_dates gtfs_calendar_dates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_calendar_dates
    ADD CONSTRAINT gtfs_calendar_dates_pkey PRIMARY KEY (id);


--
-- Name: gtfs_calendar gtfs_calendar_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_calendar
    ADD CONSTRAINT gtfs_calendar_pkey PRIMARY KEY (id);


--
-- Name: gtfs_stop_times gtfs_stop_times_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_stop_times
    ADD CONSTRAINT gtfs_stop_times_pkey PRIMARY KEY (id);


--
-- Name: gtfs_stops gtfs_stops_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_stops
    ADD CONSTRAINT gtfs_stops_pkey PRIMARY KEY (id);


--
-- Name: gtfs_trips gtfs_trips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_trips
    ADD CONSTRAINT gtfs_trips_pkey PRIMARY KEY (id);


--
-- Name: logs_import logs_import_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs_import
    ADD CONSTRAINT logs_import_pkey PRIMARY KEY (id);


--
-- Name: metrics metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY (id);


--
-- Name: multi_validation multi_validation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.multi_validation
    ADD CONSTRAINT multi_validation_pkey PRIMARY KEY (id);


--
-- Name: notification_subscription notification_subscription_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_subscription
    ADD CONSTRAINT notification_subscription_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: oban_peers oban_peers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);


--
-- Name: region region_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.region
    ADD CONSTRAINT region_pkey PRIMARY KEY (id);


--
-- Name: resource_history resource_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_history
    ADD CONSTRAINT resource_history_pkey PRIMARY KEY (id);


--
-- Name: resource_metadata resource_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_metadata
    ADD CONSTRAINT resource_metadata_pkey PRIMARY KEY (id);


--
-- Name: resource resource_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource
    ADD CONSTRAINT resource_pkey PRIMARY KEY (id);


--
-- Name: resource_unavailability resource_unavailability_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_unavailability
    ADD CONSTRAINT resource_unavailability_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: stats_history stats_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stats_history
    ADD CONSTRAINT stats_history_pkey PRIMARY KEY (id);


--
-- Name: aom_composition_res_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX aom_composition_res_id_index ON public.aom USING btree (composition_res_id);


--
-- Name: aom_geom_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX aom_geom_index ON public.aom USING gist (geom);


--
-- Name: commune_departement_insee_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commune_departement_insee_index ON public.commune USING btree (departement_insee);


--
-- Name: commune_geom_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX commune_geom_index ON public.commune USING gist (geom);


--
-- Name: commune_insee_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX commune_insee_index ON public.commune USING btree (insee);


--
-- Name: commune_siren_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX commune_siren_index ON public.commune USING btree (siren);


--
-- Name: contact_datagouv_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_datagouv_user_id_index ON public.contact USING btree (datagouv_user_id);


--
-- Name: contact_email_hash_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX contact_email_hash_index ON public.contact USING btree (email_hash);


--
-- Name: data_conversion_convert_from_convert_to_converter_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX data_conversion_convert_from_convert_to_converter_index ON public.data_conversion USING btree (convert_from, convert_to, converter);


--
-- Name: data_conversion_convert_from_convert_to_converter_resource_hist; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX data_conversion_convert_from_convert_to_converter_resource_hist ON public.data_conversion USING btree (convert_from, convert_to, converter, resource_history_uuid);


--
-- Name: dataset_aom_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_aom_id_index ON public.dataset USING btree (aom_id);


--
-- Name: dataset_aom_legal_owner_aom_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_aom_legal_owner_aom_id_index ON public.dataset_aom_legal_owner USING btree (aom_id);


--
-- Name: dataset_aom_legal_owner_dataset_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_aom_legal_owner_dataset_id_index ON public.dataset_aom_legal_owner USING btree (dataset_id);


--
-- Name: dataset_custom_tags_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_custom_tags_index ON public.dataset USING gin (custom_tags);


--
-- Name: dataset_datagouv_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dataset_datagouv_id_index ON public.dataset USING btree (datagouv_id);


--
-- Name: dataset_history_dataset_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_history_dataset_id_index ON public.dataset_history USING btree (dataset_id);


--
-- Name: dataset_history_payload_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_history_payload_slug ON public.dataset_history USING btree (((payload ->> 'slug'::text)));


--
-- Name: dataset_history_resources_dataset_history_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_history_resources_dataset_history_id_index ON public.dataset_history_resources USING btree (dataset_history_id);


--
-- Name: dataset_history_resources_resource_history_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_history_resources_resource_history_id_index ON public.dataset_history_resources USING btree (resource_history_id);


--
-- Name: dataset_history_resources_resource_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_history_resources_resource_id_index ON public.dataset_history_resources USING btree (resource_id);


--
-- Name: dataset_history_resources_resource_metadata_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_history_resources_resource_metadata_id_index ON public.dataset_history_resources USING btree (resource_metadata_id);


--
-- Name: dataset_history_resources_validation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_history_resources_validation_id_index ON public.dataset_history_resources USING btree (validation_id);


--
-- Name: dataset_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_id_idx ON public.dataset_geographic_view USING btree (dataset_id);


--
-- Name: dataset_organization_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_organization_id_index ON public.dataset USING btree (organization_id);


--
-- Name: dataset_region_legal_owner_dataset_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_region_legal_owner_dataset_id_index ON public.dataset_region_legal_owner USING btree (dataset_id);


--
-- Name: dataset_region_legal_owner_region_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_region_legal_owner_region_id_index ON public.dataset_region_legal_owner USING btree (region_id);


--
-- Name: dataset_score_dataset_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_score_dataset_id_index ON public.dataset_score USING btree (dataset_id);


--
-- Name: dataset_score_topic_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_score_topic_index ON public.dataset_score USING btree (topic);


--
-- Name: dataset_search_vector_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX dataset_search_vector_index ON public.dataset USING gin (search_vector);


--
-- Name: dataset_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX dataset_slug_index ON public.dataset USING btree (slug);


--
-- Name: departement_insee_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX departement_insee_index ON public.departement USING btree (insee);


--
-- Name: departement_nom_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX departement_nom_index ON public.departement USING btree (nom);


--
-- Name: departement_region_insee_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX departement_region_insee_index ON public.departement USING btree (region_insee);


--
-- Name: departement_zone_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX departement_zone_index ON public.departement USING btree (zone);


--
-- Name: indexed_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX indexed_name_index ON public.places USING gin (indexed_name public.gin_trgm_ops);


--
-- Name: metrics_target_event_period_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX metrics_target_event_period_index ON public.metrics USING btree (target, event, period);


--
-- Name: multi_validation_resource_history_id_validator_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX multi_validation_resource_history_id_validator_index ON public.multi_validation USING btree (resource_history_id, validator);


--
-- Name: multi_validation_resource_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX multi_validation_resource_id_index ON public.multi_validation USING btree (resource_id);


--
-- Name: notification_subscription_contact_id_dataset_id_reason_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX notification_subscription_contact_id_dataset_id_reason_index ON public.notification_subscription USING btree (contact_id, dataset_id, reason);


--
-- Name: notification_subscription_contact_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_subscription_contact_id_index ON public.notification_subscription USING btree (contact_id);


--
-- Name: notification_subscription_dataset_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notification_subscription_dataset_id_index ON public.notification_subscription USING btree (dataset_id);


--
-- Name: notifications_dataset_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_dataset_id_index ON public.notifications USING btree (dataset_id);


--
-- Name: notifications_email_hash_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_email_hash_index ON public.notifications USING btree (email_hash);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


--
-- Name: organization_slug_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX organization_slug_index ON public.organization USING btree (slug);


--
-- Name: region_geom_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX region_geom_index ON public.region USING gist (geom);


--
-- Name: region_insee_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX region_insee_index ON public.region USING btree (insee);


--
-- Name: region_nom_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX region_nom_index ON public.region USING btree (nom);


--
-- Name: resource_dataset_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_dataset_id_index ON public.resource USING btree (dataset_id);


--
-- Name: resource_format_dataset_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_format_dataset_id_index ON public.resource USING btree (format, dataset_id);


--
-- Name: resource_history_datagouv_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_history_datagouv_id_index ON public.resource_history USING btree (datagouv_id);


--
-- Name: resource_history_payload_dataset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_history_payload_dataset_id ON public.resource_history USING btree ((((payload ->> 'dataset_id'::text))::bigint));


--
-- Name: resource_history_payload_format; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_history_payload_format ON public.resource_history USING btree (((payload ->> 'format'::text)));


--
-- Name: resource_history_resource_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_history_resource_id_index ON public.resource_history USING btree (resource_id);


--
-- Name: resource_metadata_features_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_metadata_features_idx ON public.resource_metadata USING gin (features);


--
-- Name: resource_metadata_modes_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_metadata_modes_idx ON public.resource_metadata USING gin (modes);


--
-- Name: resource_metadata_multi_validation_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_metadata_multi_validation_id_index ON public.resource_metadata USING btree (multi_validation_id);


--
-- Name: resource_metadata_resource_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_metadata_resource_id_index ON public.resource_metadata USING btree (resource_id);


--
-- Name: resource_related_reason_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_related_reason_index ON public.resource_related USING btree (reason);


--
-- Name: resource_related_resource_src_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_related_resource_src_id_index ON public.resource_related USING btree (resource_src_id);


--
-- Name: resource_unavailability_resource_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX resource_unavailability_resource_id_index ON public.resource_unavailability USING btree (resource_id);


--
-- Name: stats_history_timestamp_metric_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stats_history_timestamp_metric_index ON public.stats_history USING btree ("timestamp", metric);


--
-- Name: aom aom_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER aom_update_trigger AFTER INSERT OR UPDATE ON public.aom FOR EACH ROW EXECUTE FUNCTION public.aom_update();


--
-- Name: dataset_communes dataset_communes_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER dataset_communes_update AFTER INSERT OR UPDATE ON public.dataset_communes FOR EACH ROW EXECUTE FUNCTION public.dataset_communes_update();


--
-- Name: dataset dataset_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER dataset_update_trigger BEFORE INSERT OR UPDATE ON public.dataset FOR EACH ROW EXECUTE FUNCTION public.dataset_search_update();


--
-- Name: oban_jobs oban_notify; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER oban_notify AFTER INSERT ON public.oban_jobs FOR EACH ROW EXECUTE FUNCTION public.oban_jobs_notify();


--
-- Name: dataset refresh_dataset_geographic_view_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER refresh_dataset_geographic_view_trigger AFTER INSERT OR DELETE OR UPDATE ON public.dataset FOR EACH STATEMENT EXECUTE FUNCTION public.refresh_dataset_geographic_view();


--
-- Name: aom refresh_places_aom_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER refresh_places_aom_trigger AFTER INSERT OR DELETE OR UPDATE ON public.aom FOR EACH STATEMENT EXECUTE FUNCTION public.refresh_places();


--
-- Name: commune refresh_places_commune_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER refresh_places_commune_trigger AFTER INSERT OR DELETE OR UPDATE ON public.commune FOR EACH STATEMENT EXECUTE FUNCTION public.refresh_places();


--
-- Name: region refresh_places_region_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER refresh_places_region_trigger AFTER INSERT OR DELETE OR UPDATE ON public.region FOR EACH STATEMENT EXECUTE FUNCTION public.refresh_places();


--
-- Name: region region_update_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER region_update_trigger AFTER INSERT OR UPDATE ON public.region FOR EACH ROW EXECUTE FUNCTION public.region_update();


--
-- Name: aom aom_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aom
    ADD CONSTRAINT aom_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.region(id);


--
-- Name: commune commune_aom_res_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commune
    ADD CONSTRAINT commune_aom_res_id_fkey FOREIGN KEY (aom_res_id) REFERENCES public.aom(composition_res_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: commune commune_departement_insee_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commune
    ADD CONSTRAINT commune_departement_insee_fkey FOREIGN KEY (departement_insee) REFERENCES public.departement(insee);


--
-- Name: commune commune_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commune
    ADD CONSTRAINT commune_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.region(id);


--
-- Name: contacts_organizations contacts_organizations_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_organizations
    ADD CONSTRAINT contacts_organizations_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contact(id) ON DELETE CASCADE;


--
-- Name: contacts_organizations contacts_organizations_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts_organizations
    ADD CONSTRAINT contacts_organizations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: data_import data_import_resource_history_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_import
    ADD CONSTRAINT data_import_resource_history_id_fkey FOREIGN KEY (resource_history_id) REFERENCES public.resource_history(id);


--
-- Name: dataset dataset_aom_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset
    ADD CONSTRAINT dataset_aom_id_fkey FOREIGN KEY (aom_id) REFERENCES public.aom(id);


--
-- Name: dataset_aom_legal_owner dataset_aom_legal_owner_aom_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_aom_legal_owner
    ADD CONSTRAINT dataset_aom_legal_owner_aom_id_fkey FOREIGN KEY (aom_id) REFERENCES public.aom(id) ON DELETE CASCADE;


--
-- Name: dataset_aom_legal_owner dataset_aom_legal_owner_dataset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_aom_legal_owner
    ADD CONSTRAINT dataset_aom_legal_owner_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE CASCADE;


--
-- Name: dataset_communes dataset_communes_commune_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_communes
    ADD CONSTRAINT dataset_communes_commune_id_fkey FOREIGN KEY (commune_id) REFERENCES public.commune(id) ON DELETE CASCADE;


--
-- Name: dataset_communes dataset_communes_dataset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_communes
    ADD CONSTRAINT dataset_communes_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE CASCADE;


--
-- Name: dataset_history dataset_history_dataset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history
    ADD CONSTRAINT dataset_history_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE SET NULL;


--
-- Name: dataset_history_resources dataset_history_resources_dataset_history_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history_resources
    ADD CONSTRAINT dataset_history_resources_dataset_history_id_fkey FOREIGN KEY (dataset_history_id) REFERENCES public.dataset_history(id);


--
-- Name: dataset_history_resources dataset_history_resources_resource_history_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history_resources
    ADD CONSTRAINT dataset_history_resources_resource_history_id_fkey FOREIGN KEY (resource_history_id) REFERENCES public.resource_history(id) ON DELETE SET NULL;


--
-- Name: dataset_history_resources dataset_history_resources_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history_resources
    ADD CONSTRAINT dataset_history_resources_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resource(id) ON DELETE SET NULL;


--
-- Name: dataset_history_resources dataset_history_resources_resource_metadata_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history_resources
    ADD CONSTRAINT dataset_history_resources_resource_metadata_id_fkey FOREIGN KEY (resource_metadata_id) REFERENCES public.resource_metadata(id) ON DELETE SET NULL;


--
-- Name: dataset_history_resources dataset_history_resources_validation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_history_resources
    ADD CONSTRAINT dataset_history_resources_validation_id_fkey FOREIGN KEY (validation_id) REFERENCES public.multi_validation(id) ON DELETE SET NULL;


--
-- Name: dataset dataset_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset
    ADD CONSTRAINT dataset_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.region(id);


--
-- Name: dataset_region_legal_owner dataset_region_legal_owner_dataset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_region_legal_owner
    ADD CONSTRAINT dataset_region_legal_owner_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE CASCADE;


--
-- Name: dataset_region_legal_owner dataset_region_legal_owner_region_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_region_legal_owner
    ADD CONSTRAINT dataset_region_legal_owner_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.region(id) ON DELETE CASCADE;


--
-- Name: dataset_score dataset_score_dataset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dataset_score
    ADD CONSTRAINT dataset_score_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE CASCADE;


--
-- Name: departement departement_chef_lieu_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departement
    ADD CONSTRAINT departement_chef_lieu_fkey FOREIGN KEY (chef_lieu) REFERENCES public.commune(insee) ON DELETE CASCADE;


--
-- Name: departement departement_region_insee_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departement
    ADD CONSTRAINT departement_region_insee_fkey FOREIGN KEY (region_insee) REFERENCES public.region(insee);


--
-- Name: geo_data geo_data_geo_data_import_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geo_data
    ADD CONSTRAINT geo_data_geo_data_import_id_fkey FOREIGN KEY (geo_data_import_id) REFERENCES public.geo_data_import(id) ON DELETE CASCADE;


--
-- Name: geo_data_import geo_data_import_resource_history_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geo_data_import
    ADD CONSTRAINT geo_data_import_resource_history_id_fkey FOREIGN KEY (resource_history_id) REFERENCES public.resource_history(id);


--
-- Name: gtfs_calendar gtfs_calendar_data_import_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_calendar
    ADD CONSTRAINT gtfs_calendar_data_import_id_fkey FOREIGN KEY (data_import_id) REFERENCES public.data_import(id) ON DELETE CASCADE;


--
-- Name: gtfs_calendar_dates gtfs_calendar_dates_data_import_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_calendar_dates
    ADD CONSTRAINT gtfs_calendar_dates_data_import_id_fkey FOREIGN KEY (data_import_id) REFERENCES public.data_import(id) ON DELETE CASCADE;


--
-- Name: gtfs_stop_times gtfs_stop_times_data_import_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_stop_times
    ADD CONSTRAINT gtfs_stop_times_data_import_id_fkey FOREIGN KEY (data_import_id) REFERENCES public.data_import(id) ON DELETE CASCADE;


--
-- Name: gtfs_stops gtfs_stops_data_import_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_stops
    ADD CONSTRAINT gtfs_stops_data_import_id_fkey FOREIGN KEY (data_import_id) REFERENCES public.data_import(id) ON DELETE CASCADE;


--
-- Name: gtfs_trips gtfs_trips_data_import_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gtfs_trips
    ADD CONSTRAINT gtfs_trips_data_import_id_fkey FOREIGN KEY (data_import_id) REFERENCES public.data_import(id) ON DELETE CASCADE;


--
-- Name: logs_import logs_import_dataset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs_import
    ADD CONSTRAINT logs_import_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE CASCADE;


--
-- Name: multi_validation multi_validation_resource_history_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.multi_validation
    ADD CONSTRAINT multi_validation_resource_history_id_fkey FOREIGN KEY (resource_history_id) REFERENCES public.resource_history(id) ON DELETE CASCADE;


--
-- Name: multi_validation multi_validation_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.multi_validation
    ADD CONSTRAINT multi_validation_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resource(id) ON DELETE CASCADE;


--
-- Name: multi_validation multi_validation_secondary_resource_history_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.multi_validation
    ADD CONSTRAINT multi_validation_secondary_resource_history_id_fkey FOREIGN KEY (secondary_resource_history_id) REFERENCES public.resource_history(id) ON DELETE CASCADE;


--
-- Name: multi_validation multi_validation_secondary_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.multi_validation
    ADD CONSTRAINT multi_validation_secondary_resource_id_fkey FOREIGN KEY (secondary_resource_id) REFERENCES public.resource(id) ON DELETE CASCADE;


--
-- Name: notification_subscription notification_subscription_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_subscription
    ADD CONSTRAINT notification_subscription_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contact(id) ON DELETE CASCADE;


--
-- Name: notification_subscription notification_subscription_dataset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_subscription
    ADD CONSTRAINT notification_subscription_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_dataset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id) ON DELETE SET NULL;


--
-- Name: resource resource_dataset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource
    ADD CONSTRAINT resource_dataset_id_fkey FOREIGN KEY (dataset_id) REFERENCES public.dataset(id);


--
-- Name: resource_history resource_history_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_history
    ADD CONSTRAINT resource_history_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resource(id) ON DELETE SET NULL;


--
-- Name: resource_metadata resource_metadata_multi_validation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_metadata
    ADD CONSTRAINT resource_metadata_multi_validation_id_fkey FOREIGN KEY (multi_validation_id) REFERENCES public.multi_validation(id) ON DELETE CASCADE;


--
-- Name: resource_metadata resource_metadata_resource_history_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_metadata
    ADD CONSTRAINT resource_metadata_resource_history_id_fkey FOREIGN KEY (resource_history_id) REFERENCES public.resource_history(id) ON DELETE CASCADE;


--
-- Name: resource_metadata resource_metadata_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_metadata
    ADD CONSTRAINT resource_metadata_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resource(id) ON DELETE CASCADE;


--
-- Name: resource_related resource_related_resource_dst_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_related
    ADD CONSTRAINT resource_related_resource_dst_id_fkey FOREIGN KEY (resource_dst_id) REFERENCES public.resource(id);


--
-- Name: resource_related resource_related_resource_src_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_related
    ADD CONSTRAINT resource_related_resource_src_id_fkey FOREIGN KEY (resource_src_id) REFERENCES public.resource(id);


--
-- Name: resource_unavailability resource_unavailability_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_unavailability
    ADD CONSTRAINT resource_unavailability_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resource(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

INSERT INTO public."schema_migrations" (version) VALUES (20181121164437);
INSERT INTO public."schema_migrations" (version) VALUES (20181121165604);
INSERT INTO public."schema_migrations" (version) VALUES (20181121170709);
INSERT INTO public."schema_migrations" (version) VALUES (20181121171826);
INSERT INTO public."schema_migrations" (version) VALUES (20181204093045);
INSERT INTO public."schema_migrations" (version) VALUES (20181205100445);
INSERT INTO public."schema_migrations" (version) VALUES (20181205134354);
INSERT INTO public."schema_migrations" (version) VALUES (20181205163400);
INSERT INTO public."schema_migrations" (version) VALUES (20181205164605);
INSERT INTO public."schema_migrations" (version) VALUES (20181210164424);
INSERT INTO public."schema_migrations" (version) VALUES (20181211094634);
INSERT INTO public."schema_migrations" (version) VALUES (20181211164714);
INSERT INTO public."schema_migrations" (version) VALUES (20181212091910);
INSERT INTO public."schema_migrations" (version) VALUES (20181218123622);
INSERT INTO public."schema_migrations" (version) VALUES (20181220111337);
INSERT INTO public."schema_migrations" (version) VALUES (20190108103116);
INSERT INTO public."schema_migrations" (version) VALUES (20190130145745);
INSERT INTO public."schema_migrations" (version) VALUES (20190204155646);
INSERT INTO public."schema_migrations" (version) VALUES (20190207164219);
INSERT INTO public."schema_migrations" (version) VALUES (20190227165217);
INSERT INTO public."schema_migrations" (version) VALUES (20190402122703);
INSERT INTO public."schema_migrations" (version) VALUES (20190408091202);
INSERT INTO public."schema_migrations" (version) VALUES (20190424095327);
INSERT INTO public."schema_migrations" (version) VALUES (20190425142259);
INSERT INTO public."schema_migrations" (version) VALUES (20190506153738);
INSERT INTO public."schema_migrations" (version) VALUES (20190509163526);
INSERT INTO public."schema_migrations" (version) VALUES (20190516142725);
INSERT INTO public."schema_migrations" (version) VALUES (20190703092429);
INSERT INTO public."schema_migrations" (version) VALUES (20190910091521);
INSERT INTO public."schema_migrations" (version) VALUES (20190911085235);
INSERT INTO public."schema_migrations" (version) VALUES (20191216144800);
INSERT INTO public."schema_migrations" (version) VALUES (20200106094910);
INSERT INTO public."schema_migrations" (version) VALUES (20200110124026);
INSERT INTO public."schema_migrations" (version) VALUES (20200114101848);
INSERT INTO public."schema_migrations" (version) VALUES (20200114143832);
INSERT INTO public."schema_migrations" (version) VALUES (20200116092044);
INSERT INTO public."schema_migrations" (version) VALUES (20200116163306);
INSERT INTO public."schema_migrations" (version) VALUES (20200120092242);
INSERT INTO public."schema_migrations" (version) VALUES (20200120154256);
INSERT INTO public."schema_migrations" (version) VALUES (20200130152852);
INSERT INTO public."schema_migrations" (version) VALUES (20200212092113);
INSERT INTO public."schema_migrations" (version) VALUES (20200217142350);
INSERT INTO public."schema_migrations" (version) VALUES (20200220141013);
INSERT INTO public."schema_migrations" (version) VALUES (20200224093551);
INSERT INTO public."schema_migrations" (version) VALUES (20200225140241);
INSERT INTO public."schema_migrations" (version) VALUES (20200311095433);
INSERT INTO public."schema_migrations" (version) VALUES (20200420082026);
INSERT INTO public."schema_migrations" (version) VALUES (20200429171646);
INSERT INTO public."schema_migrations" (version) VALUES (20200505124346);
INSERT INTO public."schema_migrations" (version) VALUES (20200527084259);
INSERT INTO public."schema_migrations" (version) VALUES (20200603103539);
INSERT INTO public."schema_migrations" (version) VALUES (20200603130643);
INSERT INTO public."schema_migrations" (version) VALUES (20200608155921);
INSERT INTO public."schema_migrations" (version) VALUES (20200610162056);
INSERT INTO public."schema_migrations" (version) VALUES (20200616101043);
INSERT INTO public."schema_migrations" (version) VALUES (20200622141231);
INSERT INTO public."schema_migrations" (version) VALUES (20200623112618);
INSERT INTO public."schema_migrations" (version) VALUES (20200623134041);
INSERT INTO public."schema_migrations" (version) VALUES (20200623162648);
INSERT INTO public."schema_migrations" (version) VALUES (20200630154908);
INSERT INTO public."schema_migrations" (version) VALUES (20200703080414);
INSERT INTO public."schema_migrations" (version) VALUES (20200818124059);
INSERT INTO public."schema_migrations" (version) VALUES (20200907134321);
INSERT INTO public."schema_migrations" (version) VALUES (20200908085058);
INSERT INTO public."schema_migrations" (version) VALUES (20201103174924);
INSERT INTO public."schema_migrations" (version) VALUES (20201103183100);
INSERT INTO public."schema_migrations" (version) VALUES (20201112110459);
INSERT INTO public."schema_migrations" (version) VALUES (20201209152013);
INSERT INTO public."schema_migrations" (version) VALUES (20201214163517);
INSERT INTO public."schema_migrations" (version) VALUES (20210126172850);
INSERT INTO public."schema_migrations" (version) VALUES (20210512142927);
INSERT INTO public."schema_migrations" (version) VALUES (20210615132842);
INSERT INTO public."schema_migrations" (version) VALUES (20210622150648);
INSERT INTO public."schema_migrations" (version) VALUES (20210623140048);
INSERT INTO public."schema_migrations" (version) VALUES (20210630130031);
INSERT INTO public."schema_migrations" (version) VALUES (20210811122529);
INSERT INTO public."schema_migrations" (version) VALUES (20211006144855);
INSERT INTO public."schema_migrations" (version) VALUES (20211018122851);
INSERT INTO public."schema_migrations" (version) VALUES (20211021094750);
INSERT INTO public."schema_migrations" (version) VALUES (20211122101004);
INSERT INTO public."schema_migrations" (version) VALUES (20211130094242);
INSERT INTO public."schema_migrations" (version) VALUES (20211209090542);
INSERT INTO public."schema_migrations" (version) VALUES (20211209121042);
INSERT INTO public."schema_migrations" (version) VALUES (20211210082242);
INSERT INTO public."schema_migrations" (version) VALUES (20211214142804);
INSERT INTO public."schema_migrations" (version) VALUES (20220104092238);
INSERT INTO public."schema_migrations" (version) VALUES (20220118101217);
INSERT INTO public."schema_migrations" (version) VALUES (20220124133742);
INSERT INTO public."schema_migrations" (version) VALUES (20220126101800);
INSERT INTO public."schema_migrations" (version) VALUES (20220208143147);
INSERT INTO public."schema_migrations" (version) VALUES (20220210142527);
INSERT INTO public."schema_migrations" (version) VALUES (20220214161600);
INSERT INTO public."schema_migrations" (version) VALUES (20220225104500);
INSERT INTO public."schema_migrations" (version) VALUES (20220301085100);
INSERT INTO public."schema_migrations" (version) VALUES (20220321151717);
INSERT INTO public."schema_migrations" (version) VALUES (20220322090153);
INSERT INTO public."schema_migrations" (version) VALUES (20220322135059);
INSERT INTO public."schema_migrations" (version) VALUES (20220329113451);
INSERT INTO public."schema_migrations" (version) VALUES (20220406125936);
INSERT INTO public."schema_migrations" (version) VALUES (20220412131157);
INSERT INTO public."schema_migrations" (version) VALUES (20220419124355);
INSERT INTO public."schema_migrations" (version) VALUES (20220429092956);
INSERT INTO public."schema_migrations" (version) VALUES (20220502083641);
INSERT INTO public."schema_migrations" (version) VALUES (20220502130846);
INSERT INTO public."schema_migrations" (version) VALUES (20220505115659);
INSERT INTO public."schema_migrations" (version) VALUES (20220505121748);
INSERT INTO public."schema_migrations" (version) VALUES (20220510124001);
INSERT INTO public."schema_migrations" (version) VALUES (20220523132328);
INSERT INTO public."schema_migrations" (version) VALUES (20220525084346);
INSERT INTO public."schema_migrations" (version) VALUES (20220531123506);
INSERT INTO public."schema_migrations" (version) VALUES (20220601135310);
INSERT INTO public."schema_migrations" (version) VALUES (20220615090656);
INSERT INTO public."schema_migrations" (version) VALUES (20220615123711);
INSERT INTO public."schema_migrations" (version) VALUES (20220922134600);
INSERT INTO public."schema_migrations" (version) VALUES (20220923080044);
INSERT INTO public."schema_migrations" (version) VALUES (20220923080526);
INSERT INTO public."schema_migrations" (version) VALUES (20220929073801);
INSERT INTO public."schema_migrations" (version) VALUES (20220930122054);
INSERT INTO public."schema_migrations" (version) VALUES (20221004125601);
INSERT INTO public."schema_migrations" (version) VALUES (20221004135750);
INSERT INTO public."schema_migrations" (version) VALUES (20221004151551);
INSERT INTO public."schema_migrations" (version) VALUES (20221005125656);
INSERT INTO public."schema_migrations" (version) VALUES (20221010144415);
INSERT INTO public."schema_migrations" (version) VALUES (20221031094523);
INSERT INTO public."schema_migrations" (version) VALUES (20221110101806);
INSERT INTO public."schema_migrations" (version) VALUES (20221129131631);
INSERT INTO public."schema_migrations" (version) VALUES (20221201165336);
INSERT INTO public."schema_migrations" (version) VALUES (20221206132945);
INSERT INTO public."schema_migrations" (version) VALUES (20221206135302);
INSERT INTO public."schema_migrations" (version) VALUES (20221208083708);
INSERT INTO public."schema_migrations" (version) VALUES (20221228090455);
INSERT INTO public."schema_migrations" (version) VALUES (20221228090553);
INSERT INTO public."schema_migrations" (version) VALUES (20221228142229);
INSERT INTO public."schema_migrations" (version) VALUES (20230103165252);
INSERT INTO public."schema_migrations" (version) VALUES (20230110074451);
INSERT INTO public."schema_migrations" (version) VALUES (20230111115335);
INSERT INTO public."schema_migrations" (version) VALUES (20230112132326);
INSERT INTO public."schema_migrations" (version) VALUES (20230120093740);
INSERT INTO public."schema_migrations" (version) VALUES (20230124110826);
INSERT INTO public."schema_migrations" (version) VALUES (20230124131704);
INSERT INTO public."schema_migrations" (version) VALUES (20230125145703);
INSERT INTO public."schema_migrations" (version) VALUES (20230202090645);
INSERT INTO public."schema_migrations" (version) VALUES (20230206131831);
INSERT INTO public."schema_migrations" (version) VALUES (20230220102200);
INSERT INTO public."schema_migrations" (version) VALUES (20230302084455);
INSERT INTO public."schema_migrations" (version) VALUES (20230308085359);
INSERT INTO public."schema_migrations" (version) VALUES (20230309102424);
INSERT INTO public."schema_migrations" (version) VALUES (20230322080214);
INSERT INTO public."schema_migrations" (version) VALUES (20230327135824);
INSERT INTO public."schema_migrations" (version) VALUES (20230329071947);
INSERT INTO public."schema_migrations" (version) VALUES (20230404074406);
INSERT INTO public."schema_migrations" (version) VALUES (20230412080437);
INSERT INTO public."schema_migrations" (version) VALUES (20230420134229);
INSERT INTO public."schema_migrations" (version) VALUES (20230427083218);
INSERT INTO public."schema_migrations" (version) VALUES (20230524122950);
INSERT INTO public."schema_migrations" (version) VALUES (20230525152222);
INSERT INTO public."schema_migrations" (version) VALUES (20230609122110);
INSERT INTO public."schema_migrations" (version) VALUES (20230623121709);
INSERT INTO public."schema_migrations" (version) VALUES (20230626130232);
INSERT INTO public."schema_migrations" (version) VALUES (20230630074914);
INSERT INTO public."schema_migrations" (version) VALUES (20230719123439);
INSERT INTO public."schema_migrations" (version) VALUES (20230719124102);
INSERT INTO public."schema_migrations" (version) VALUES (20230828142610);
INSERT INTO public."schema_migrations" (version) VALUES (20230913130308);
INSERT INTO public."schema_migrations" (version) VALUES (20230925124412);
INSERT INTO public."schema_migrations" (version) VALUES (20231019121309);
INSERT INTO public."schema_migrations" (version) VALUES (20231110140739);
