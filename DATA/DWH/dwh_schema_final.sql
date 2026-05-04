--
-- PostgreSQL database dump
--

\restrict oydUtXCpwYwRpf0sjo5jvmXRu7tcmLL3Fx5H2k1hlluJhec4QIWprDTCoKeibbc

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

-- Started on 2026-05-04 21:54:04

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 220 (class 1259 OID 25400)
-- Name: dim_komoditas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dim_komoditas (
    komoditas_key integer NOT NULL,
    id_komoditas integer,
    nama_komoditas character varying(100) NOT NULL
);


ALTER TABLE public.dim_komoditas OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 25393)
-- Name: dim_prov; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dim_prov (
    prov_key integer NOT NULL,
    id_prov integer,
    nama_provinsi character varying(100) NOT NULL
);


ALTER TABLE public.dim_prov OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 25407)
-- Name: dim_waktu; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dim_waktu (
    waktu_key integer NOT NULL,
    tahun smallint NOT NULL,
    bulan smallint NOT NULL,
    kuartal smallint,
    nama_bulan character varying(20)
);


ALTER TABLE public.dim_waktu OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 25418)
-- Name: fact_supply_resilience; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fact_supply_resilience (
    fact_id integer NOT NULL,
    prov_key integer NOT NULL,
    waktu_key integer NOT NULL,
    komoditas_key integer NOT NULL,
    jumlah_penduduk bigint,
    sum_jumlah_sakit double precision,
    sum_jumlah_mati double precision,
    sum_vol_mutasi double precision,
    sum_realisasi_karkas double precision,
    avg_harga double precision,
    harga_baseline double precision,
    populasi_ternak double precision,
    avg_konsumsi_bulanan double precision,
    avg_pemotongan_bulanan double precision,
    growth_populasi double precision,
    avg_permintaan_bulanan double precision,
    avg_produksi_bulanan double precision,
    supply_risk_index double precision
);


ALTER TABLE public.fact_supply_resilience OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 25417)
-- Name: fact_supply_resilience_fact_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.fact_supply_resilience_fact_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.fact_supply_resilience_fact_id_seq OWNER TO postgres;

--
-- TOC entry 5040 (class 0 OID 0)
-- Dependencies: 222
-- Name: fact_supply_resilience_fact_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.fact_supply_resilience_fact_id_seq OWNED BY public.fact_supply_resilience.fact_id;


--
-- TOC entry 4868 (class 2604 OID 25421)
-- Name: fact_supply_resilience fact_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_supply_resilience ALTER COLUMN fact_id SET DEFAULT nextval('public.fact_supply_resilience_fact_id_seq'::regclass);


--
-- TOC entry 4872 (class 2606 OID 25406)
-- Name: dim_komoditas dim_komoditas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dim_komoditas
    ADD CONSTRAINT dim_komoditas_pkey PRIMARY KEY (komoditas_key);


--
-- TOC entry 4870 (class 2606 OID 25399)
-- Name: dim_prov dim_prov_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dim_prov
    ADD CONSTRAINT dim_prov_pkey PRIMARY KEY (prov_key);


--
-- TOC entry 4874 (class 2606 OID 25414)
-- Name: dim_waktu dim_waktu_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dim_waktu
    ADD CONSTRAINT dim_waktu_pkey PRIMARY KEY (waktu_key);


--
-- TOC entry 4876 (class 2606 OID 25416)
-- Name: dim_waktu dim_waktu_tahun_bulan_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dim_waktu
    ADD CONSTRAINT dim_waktu_tahun_bulan_key UNIQUE (tahun, bulan);


--
-- TOC entry 4878 (class 2606 OID 25427)
-- Name: fact_supply_resilience fact_supply_resilience_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_supply_resilience
    ADD CONSTRAINT fact_supply_resilience_pkey PRIMARY KEY (fact_id);


--
-- TOC entry 4880 (class 2606 OID 25429)
-- Name: fact_supply_resilience fact_supply_resilience_prov_key_waktu_key_komoditas_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_supply_resilience
    ADD CONSTRAINT fact_supply_resilience_prov_key_waktu_key_komoditas_key_key UNIQUE (prov_key, waktu_key, komoditas_key);


--
-- TOC entry 4881 (class 1259 OID 25447)
-- Name: idx_fact_komoditas; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fact_komoditas ON public.fact_supply_resilience USING btree (komoditas_key);


--
-- TOC entry 4882 (class 1259 OID 25445)
-- Name: idx_fact_prov; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fact_prov ON public.fact_supply_resilience USING btree (prov_key);


--
-- TOC entry 4883 (class 1259 OID 25448)
-- Name: idx_fact_risk; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fact_risk ON public.fact_supply_resilience USING btree (supply_risk_index DESC);


--
-- TOC entry 4884 (class 1259 OID 25446)
-- Name: idx_fact_waktu; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_fact_waktu ON public.fact_supply_resilience USING btree (waktu_key);


--
-- TOC entry 4885 (class 2606 OID 25440)
-- Name: fact_supply_resilience fact_supply_resilience_komoditas_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_supply_resilience
    ADD CONSTRAINT fact_supply_resilience_komoditas_key_fkey FOREIGN KEY (komoditas_key) REFERENCES public.dim_komoditas(komoditas_key);


--
-- TOC entry 4886 (class 2606 OID 25430)
-- Name: fact_supply_resilience fact_supply_resilience_prov_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_supply_resilience
    ADD CONSTRAINT fact_supply_resilience_prov_key_fkey FOREIGN KEY (prov_key) REFERENCES public.dim_prov(prov_key);


--
-- TOC entry 4887 (class 2606 OID 25435)
-- Name: fact_supply_resilience fact_supply_resilience_waktu_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fact_supply_resilience
    ADD CONSTRAINT fact_supply_resilience_waktu_key_fkey FOREIGN KEY (waktu_key) REFERENCES public.dim_waktu(waktu_key);


-- Completed on 2026-05-04 21:54:04

--
-- PostgreSQL database dump complete
--

\unrestrict oydUtXCpwYwRpf0sjo5jvmXRu7tcmLL3Fx5H2k1hlluJhec4QIWprDTCoKeibbc

