
USE TransactionRiskDB;
GO
-- PARTIE 1 — CRÉATION DES TABLES (STAR SCHEMA)

-- Suppression dans l'ordre pour éviter les erreurs FK
IF OBJECT_ID('fact_transactions', 'U') IS NOT NULL DROP TABLE fact_transactions;
IF OBJECT_ID('dim_balance',       'U') IS NOT NULL DROP TABLE dim_balance;
IF OBJECT_ID('dim_date',          'U') IS NOT NULL DROP TABLE dim_date;
IF OBJECT_ID('dim_beneficiary',   'U') IS NOT NULL DROP TABLE dim_beneficiary;
IF OBJECT_ID('dim_account',       'U') IS NOT NULL DROP TABLE dim_account;
GO

-- Dimension compte (source : GET /accounts SG DSP2)
CREATE TABLE dim_account (
    account_id      INT IDENTITY(1,1) PRIMARY KEY,
    resource_id     NVARCHAR(50)  NOT NULL UNIQUE,
    iban            NVARCHAR(34)  NOT NULL,
    currency        CHAR(3)       NOT NULL DEFAULT 'EUR',
    account_name    NVARCHAR(100) NOT NULL,
    status          NVARCHAR(20)  NOT NULL DEFAULT 'enabled'
);

-- Dimension bénéficiaire (source : creditorAccount + /trusted-beneficiaries)
CREATE TABLE dim_beneficiary (
    beneficiary_id  INT IDENTITY(1,1) PRIMARY KEY,
    creditor_name   NVARCHAR(200) NOT NULL,
    creditor_iban   NVARCHAR(34)  NOT NULL UNIQUE,
    country_code    CHAR(2)       NOT NULL DEFAULT 'FR',
    is_trusted      BIT           NOT NULL DEFAULT 0,
    first_seen      DATE          NOT NULL DEFAULT CAST(GETDATE() AS DATE)
);

-- Dimension date (source : bookingDate SG DSP2)
CREATE TABLE dim_date (
    date_id         INT IDENTITY(1,1) PRIMARY KEY,
    booking_date    DATETIME2     NOT NULL,
    value_date      DATETIME2,
    booking_day     DATE          NOT NULL,
    booking_hour    TINYINT       NOT NULL,
    day_of_week     TINYINT       NOT NULL, -- 1=Dimanche, 2=Lundi ... 7=Samedi (SQL Server)
    is_weekend      BIT           NOT NULL DEFAULT 0,
    month_num       TINYINT       NOT NULL,
    year_num        SMALLINT      NOT NULL
);

-- Dimension solde (source : GET /accounts/{id}/balances SG DSP2)
CREATE TABLE dim_balance (
    balance_id      INT IDENTITY(1,1) PRIMARY KEY,
    account_id      INT            NOT NULL REFERENCES dim_account(account_id),
    balance_type    NVARCHAR(30)   NOT NULL, -- 'closingBooked', 'interimAvailable'
    amount          DECIMAL(18,2)  NOT NULL,
    currency        CHAR(3)        NOT NULL DEFAULT 'EUR',
    reference_date  DATETIME2      NOT NULL
);

-- Table de faits (source : transactions booked SG DSP2)
CREATE TABLE fact_transactions (
    transaction_id      INT IDENTITY(1,1) PRIMARY KEY,
    sg_transaction_id   NVARCHAR(100)  NOT NULL UNIQUE,
    account_id          INT            NOT NULL REFERENCES dim_account(account_id),
    beneficiary_id      INT                     REFERENCES dim_beneficiary(beneficiary_id),
    date_id             INT            NOT NULL REFERENCES dim_date(date_id),
    amount_eur          DECIMAL(18,2)  NOT NULL,
    direction           CHAR(6)        NOT NULL CHECK (direction IN ('DEBIT','CREDIT')),
    remittance_info     NVARCHAR(500),
    booking_status      NVARCHAR(20)   NOT NULL DEFAULT 'booked',
    payment_product     NVARCHAR(50),
    balance_before      DECIMAL(18,2),
    balance_after       DECIMAL(18,2),
    risk_score          DECIMAL(5,2)   DEFAULT 0,
    is_anomaly          BIT            DEFAULT 0,
    loaded_at           DATETIME2      DEFAULT GETDATE()
);
GO

PRINT '✓ Tables créées avec succès';
GO


-- PARTIE 2 — DONNÉES MAÎTRES (comptes + bénéficiaires)

-- 3 comptes bancaires fictifs (format SG DSP2)
INSERT INTO dim_account (resource_id, iban, currency, account_name, status) VALUES
('ACC-001-PRO', 'FR7630004000031234567890143', 'EUR', 'Compte Courant Pro',  'enabled'),
('ACC-002-PRO', 'FR7630004000039876543210987', 'EUR', 'Compte Épargne Pro',  'enabled'),
('ACC-003-PRO', 'FR7614508711005432198765432', 'EUR', 'Compte Trésorerie',   'enabled');

-- Bénéficiaires de confiance (is_trusted = 1)
INSERT INTO dim_beneficiary (creditor_name, creditor_iban, country_code, is_trusted, first_seen) VALUES
('EDF Électricité de France',  'FR7610096000501234567890189', 'FR', 1, '2024-01-01'),
('Orange SA',                   'FR7617569000407654321098765', 'FR', 1, '2024-01-01'),
('Loyer Résidence Principale',  'FR7630066100410987654321098', 'FR', 1, '2024-01-01'),
('Salaire SNCF',                'FR7630004000031111111111111', 'FR', 1, '2024-01-01'),
('Remboursement CPAM',          'FR7630004000032222222222222', 'FR', 1, '2024-01-01'),
('Assurance AXA',               'FR7630004000033333333333333', 'FR', 1, '2024-01-01'),
('Mutuelle MGEN',               'FR7630004000034444444444444', 'FR', 1, '2024-01-01'),
('Netflix International',       'NL18ABNA0417164300',          'NL', 1, '2024-01-01'),
('Amazon Payments Europe',      'LU28001900400000197802',       'LU', 1, '2024-01-01'),
('Spotify AB',                  'SE4550000000058398257466',     'SE', 1, '2024-01-01');

-- Bénéficiaires suspects (is_trusted = 0)
INSERT INTO dim_beneficiary (creditor_name, creditor_iban, country_code, is_trusted, first_seen) VALUES
('Crypto Exchange Ltd',         'GB29NWBK60161331926819',        'GB', 0, '2025-01-15'),
('Trading FX International',    'DE89370400440532013000',        'DE', 0, '2025-02-03'),
('Online Casino Malta',         'MT84MALT011000012345MTLCAST001S','MT',0, '2025-03-11'),
('Société Inconnue SARL',       'FR7630004000039999999999999',   'FR', 0, '2025-01-28'),
('Wire Transfer Services',      'CY17002001280000001200527600',  'CY', 0, '2025-02-19'),
('Global Invest Corp',          'LT601010012345678901',           'LT', 0, '2025-03-05'),
('Particulier Durand Jean',     'FR7614508711001122334455667',   'FR', 0, '2025-01-07'),
('Prestation Consulting X',     'BE71096123456769',               'BE', 0, '2025-02-22');

PRINT '✓ Données maîtres insérées';
GO



-- PARTIE 3 — PROCÉDURE D'INSERTION D'UNE TRANSACTION
-- Cette procédure gère l'insertion dans dim_date ET fact_transactions
-- en une seule fois, sans doublons.

CREATE OR ALTER PROCEDURE sp_insert_transaction
    @sg_id          NVARCHAR(100),
    @resource_id    NVARCHAR(50),
    @creditor_iban  NVARCHAR(34),
    @amount         DECIMAL(18,2),
    @booking_date   DATETIME2,
    @remittance     NVARCHAR(500),
    @payment_product NVARCHAR(50),
    @balance_before DECIMAL(18,2),
    @balance_after  DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @account_id     INT;
    DECLARE @beneficiary_id INT;
    DECLARE @date_id        INT;

    -- Résolution account_id
    SELECT @account_id = account_id
    FROM dim_account WHERE resource_id = @resource_id;

    -- Résolution beneficiary_id
    SELECT @beneficiary_id = beneficiary_id
    FROM dim_beneficiary WHERE creditor_iban = @creditor_iban;

    -- Insertion dim_date
    INSERT INTO dim_date (booking_date, value_date, booking_day, booking_hour,
                          day_of_week, is_weekend, month_num, year_num)
    VALUES (
        @booking_date,
        DATEADD(HOUR, 2, @booking_date),
        CAST(@booking_date AS DATE),
        DATEPART(HOUR,    @booking_date),
        DATEPART(WEEKDAY, @booking_date),
        CASE WHEN DATEPART(WEEKDAY, @booking_date) IN (1,7) THEN 1 ELSE 0 END,
        MONTH(@booking_date),
        YEAR(@booking_date)
    );
    SET @date_id = SCOPE_IDENTITY();

    -- Insertion fact_transactions (MERGE pour éviter doublons)
    MERGE fact_transactions AS t
    USING (SELECT @sg_id AS sg_id) AS s ON t.sg_transaction_id = s.sg_id
    WHEN NOT MATCHED THEN
        INSERT (sg_transaction_id, account_id, beneficiary_id, date_id,
                amount_eur, direction, remittance_info, booking_status,
                payment_product, balance_before, balance_after)
        VALUES (@sg_id, @account_id, @beneficiary_id, @date_id,
                @amount, 'DEBIT', @remittance, 'booked',
                @payment_product, @balance_before, @balance_after);
END;
GO

PRINT '✓ Procédure stockée créée';
GO


-- PARTIE 4 — SIMULATION DES TRANSACTIONS
-- Format exact SG DSP2 (champs : transactionId, bookingDate,
-- transactionAmount, creditorName, remittanceInformationUnstructured)

-- ── TRANSACTIONS NORMALES (horaire bureau, bénéficiaires connus) ──

EXEC sp_insert_transaction 'TX-001','ACC-001-PRO','FR7610096000501234567890189', 89.50, '2025-01-06 09:15:00','Facture EDF janvier','sepa-credit-transfers',4200.00,4110.50;
EXEC sp_insert_transaction 'TX-002','ACC-001-PRO','FR7617569000407654321098765',  45.99,'2025-01-07 10:30:00','Abonnement Orange','sepa-credit-transfers',4110.50,4064.51;
EXEC sp_insert_transaction 'TX-003','ACC-001-PRO','FR7630066100410987654321098', 850.00,'2025-01-08 11:00:00','Loyer janvier 2025','sepa-credit-transfers',4064.51,3214.51;
EXEC sp_insert_transaction 'TX-004','ACC-002-PRO','FR7630004000033333333333333',  72.40,'2025-01-09 14:20:00','Assurance auto AXA','sepa-credit-transfers',6500.00,6427.60;
EXEC sp_insert_transaction 'TX-005','ACC-002-PRO','FR7630004000034444444444444',  38.00,'2025-01-10 15:45:00','Cotisation MGEN','sepa-credit-transfers',6427.60,6389.60;
EXEC sp_insert_transaction 'TX-006','ACC-001-PRO','NL18ABNA0417164300',           17.99,'2025-01-13 08:00:00','Netflix janvier','sepa-credit-transfers',3214.51,3196.52;
EXEC sp_insert_transaction 'TX-007','ACC-001-PRO','LU28001900400000197802',       65.30,'2025-01-14 09:45:00','Commande Amazon','sepa-credit-transfers',3196.52,3131.22;
EXEC sp_insert_transaction 'TX-008','ACC-003-PRO','FR7630004000031111111111111', 350.00,'2025-01-15 10:00:00','Remboursement collègue','sepa-credit-transfers',8000.00,7650.00;
EXEC sp_insert_transaction 'TX-009','ACC-002-PRO','FR7630004000032222222222222', 124.50,'2025-01-16 11:30:00','Remboursement CPAM','sepa-credit-transfers',6389.60,6265.10;
EXEC sp_insert_transaction 'TX-010','ACC-001-PRO','SE4550000000058398257466',     10.99,'2025-01-17 14:00:00','Spotify mensuel','sepa-credit-transfers',3131.22,3120.23;
EXEC sp_insert_transaction 'TX-011','ACC-003-PRO','FR7610096000501234567890189', 112.80,'2025-01-20 09:00:00','Facture EDF pro','sepa-credit-transfers',7650.00,7537.20;
EXEC sp_insert_transaction 'TX-012','ACC-001-PRO','FR7617569000407654321098765',  55.00,'2025-01-21 10:15:00','Option fibre Orange','sepa-credit-transfers',3120.23,3065.23;
EXEC sp_insert_transaction 'TX-013','ACC-002-PRO','FR7630066100410987654321098', 850.00,'2025-02-05 11:00:00','Loyer février 2025','sepa-credit-transfers',6265.10,5415.10;
EXEC sp_insert_transaction 'TX-014','ACC-001-PRO','FR7630004000033333333333333',  72.40,'2025-02-06 14:20:00','Assurance auto février','sepa-credit-transfers',3065.23,2992.83;
EXEC sp_insert_transaction 'TX-015','ACC-003-PRO','LU28001900400000197802',       89.99,'2025-02-07 15:00:00','Amazon commande','sepa-credit-transfers',7537.20,7447.21;
EXEC sp_insert_transaction 'TX-016','ACC-002-PRO','FR7610096000501234567890189',  95.20,'2025-02-10 09:30:00','EDF février','sepa-credit-transfers',5415.10,5319.90;
EXEC sp_insert_transaction 'TX-017','ACC-001-PRO','NL18ABNA0417164300',           17.99,'2025-02-13 08:00:00','Netflix février','sepa-credit-transfers',2992.83,2974.84;
EXEC sp_insert_transaction 'TX-018','ACC-003-PRO','SE4550000000058398257466',     10.99,'2025-02-14 09:00:00','Spotify février','sepa-credit-transfers',7447.21,7436.22;
EXEC sp_insert_transaction 'TX-019','ACC-001-PRO','FR7630004000032222222222222', 210.00,'2025-02-17 10:30:00','Remboursement CPAM','sepa-credit-transfers',2974.84,2764.84;
EXEC sp_insert_transaction 'TX-020','ACC-002-PRO','FR7617569000407654321098765',  45.99,'2025-02-18 11:45:00','Orange février','sepa-credit-transfers',5319.90,5273.91;
EXEC sp_insert_transaction 'TX-021','ACC-001-PRO','FR7630066100410987654321098', 850.00,'2025-03-05 10:00:00','Loyer mars 2025','sepa-credit-transfers',2764.84,1914.84;
EXEC sp_insert_transaction 'TX-022','ACC-003-PRO','FR7630004000033333333333333',  72.40,'2025-03-06 14:00:00','AXA mars','sepa-credit-transfers',7436.22,7363.82;
EXEC sp_insert_transaction 'TX-023','ACC-002-PRO','FR7630004000034444444444444',  38.00,'2025-03-07 15:30:00','MGEN mars','sepa-credit-transfers',5273.91,5235.91;
EXEC sp_insert_transaction 'TX-024','ACC-001-PRO','LU28001900400000197802',       45.00,'2025-03-10 09:15:00','Amazon livres','sepa-credit-transfers',1914.84,1869.84;
EXEC sp_insert_transaction 'TX-025','ACC-003-PRO','FR7610096000501234567890189', 101.60,'2025-03-12 10:00:00','EDF mars','sepa-credit-transfers',7363.82,7262.22;

-- Transactions normales supplémentaires (volume)
EXEC sp_insert_transaction 'TX-026','ACC-001-PRO','FR7617569000407654321098765',  45.99,'2025-03-13 11:00:00','Orange mars','sepa-credit-transfers',1869.84,1823.85;
EXEC sp_insert_transaction 'TX-027','ACC-002-PRO','SE4550000000058398257466',     10.99,'2025-03-14 13:00:00','Spotify mars','sepa-credit-transfers',5235.91,5224.92;
EXEC sp_insert_transaction 'TX-028','ACC-003-PRO','NL18ABNA0417164300',           17.99,'2025-03-17 08:30:00','Netflix mars','sepa-credit-transfers',7262.22,7244.23;
EXEC sp_insert_transaction 'TX-029','ACC-001-PRO','FR7630004000033333333333333',  72.40,'2025-04-07 14:20:00','AXA avril','sepa-credit-transfers',1823.85,1751.45;
EXEC sp_insert_transaction 'TX-030','ACC-002-PRO','FR7630066100410987654321098', 850.00,'2025-04-05 10:00:00','Loyer avril 2025','sepa-credit-transfers',5224.92,4374.92;
EXEC sp_insert_transaction 'TX-031','ACC-001-PRO','FR7610096000501234567890189',  88.40,'2025-04-08 09:00:00','EDF avril','sepa-credit-transfers',1751.45,1663.05;
EXEC sp_insert_transaction 'TX-032','ACC-003-PRO','LU28001900400000197802',      130.00,'2025-04-10 10:30:00','Amazon électronique','sepa-credit-transfers',7244.23,7114.23;
EXEC sp_insert_transaction 'TX-033','ACC-002-PRO','FR7617569000407654321098765',  45.99,'2025-04-11 11:00:00','Orange avril','sepa-credit-transfers',4374.92,4328.93;
EXEC sp_insert_transaction 'TX-034','ACC-001-PRO','NL18ABNA0417164300',           17.99,'2025-04-14 08:00:00','Netflix avril','sepa-credit-transfers',1663.05,1645.06;
EXEC sp_insert_transaction 'TX-035','ACC-003-PRO','SE4550000000058398257466',     10.99,'2025-04-15 09:00:00','Spotify avril','sepa-credit-transfers',7114.23,7103.24;
EXEC sp_insert_transaction 'TX-036','ACC-002-PRO','FR7630004000032222222222222', 175.50,'2025-04-16 10:30:00','CPAM avril','sepa-credit-transfers',4328.93,4153.43;
EXEC sp_insert_transaction 'TX-037','ACC-001-PRO','FR7630004000034444444444444',  38.00,'2025-04-17 14:00:00','MGEN avril','sepa-credit-transfers',1645.06,1607.06;
EXEC sp_insert_transaction 'TX-038','ACC-003-PRO','FR7630004000033333333333333',  72.40,'2025-05-06 09:00:00','AXA mai','sepa-credit-transfers',7103.24,7030.84;
EXEC sp_insert_transaction 'TX-039','ACC-002-PRO','FR7630066100410987654321098', 850.00,'2025-05-05 10:00:00','Loyer mai 2025','sepa-credit-transfers',4153.43,3303.43;
EXEC sp_insert_transaction 'TX-040','ACC-001-PRO','FR7610096000501234567890189',  76.20,'2025-05-07 11:00:00','EDF mai','sepa-credit-transfers',1607.06,1530.86;
EXEC sp_insert_transaction 'TX-041','ACC-003-PRO','FR7617569000407654321098765',  55.00,'2025-05-08 14:00:00','Orange mai','sepa-credit-transfers',7030.84,6975.84;
EXEC sp_insert_transaction 'TX-042','ACC-002-PRO','NL18ABNA0417164300',           17.99,'2025-05-12 08:00:00','Netflix mai','sepa-credit-transfers',3303.43,3285.44;
EXEC sp_insert_transaction 'TX-043','ACC-001-PRO','LU28001900400000197802',       55.99,'2025-05-13 10:00:00','Amazon maison','sepa-credit-transfers',1530.86,1474.87;
EXEC sp_insert_transaction 'TX-044','ACC-003-PRO','SE4550000000058398257466',     10.99,'2025-05-14 09:30:00','Spotify mai','sepa-credit-transfers',6975.84,6964.85;
EXEC sp_insert_transaction 'TX-045','ACC-002-PRO','FR7630004000034444444444444',  38.00,'2025-05-15 13:00:00','MGEN mai','sepa-credit-transfers',3285.44,3247.44;
EXEC sp_insert_transaction 'TX-046','ACC-001-PRO','FR7630066100410987654321098', 850.00,'2025-06-05 10:00:00','Loyer juin 2025','sepa-credit-transfers',1474.87, 624.87;
EXEC sp_insert_transaction 'TX-047','ACC-003-PRO','FR7610096000501234567890189',  92.80,'2025-06-06 09:00:00','EDF juin','sepa-credit-transfers',6964.85,6872.05;
EXEC sp_insert_transaction 'TX-048','ACC-002-PRO','FR7617569000407654321098765',  45.99,'2025-06-09 10:30:00','Orange juin','sepa-credit-transfers',3247.44,3201.45;
EXEC sp_insert_transaction 'TX-049','ACC-001-PRO','FR7630004000032222222222222', 190.00,'2025-06-10 11:00:00','CPAM juin','sepa-credit-transfers', 624.87, 434.87;
EXEC sp_insert_transaction 'TX-050','ACC-003-PRO','LU28001900400000197802',       78.50,'2025-06-11 14:00:00','Amazon sport','sepa-credit-transfers',6872.05,6793.55;


-- ── ANOMALIE TYPE 1 — MONTANT ANORMALEMENT ÉLEVÉ ─────────────
-- Signal Z-score : montant >> moyenne du compte
-- Score attendu : 35–40 pts → niveau ÉLEVÉ

EXEC sp_insert_transaction 'TX-A01','ACC-001-PRO','FR7630004000039999999999999', 8500.00,'2025-01-22 14:30:00','Investissement urgent','sepa-credit-transfers',9000.00, 500.00;
EXEC sp_insert_transaction 'TX-A02','ACC-002-PRO','GB29NWBK60161331926819',     12000.00,'2025-02-11 15:00:00','Transfert confidentiel','sepa-credit-transfers',15000.00,3000.00;
EXEC sp_insert_transaction 'TX-A03','ACC-003-PRO','DE89370400440532013000',      7800.00,'2025-03-18 10:45:00','Virement exceptionnel','sepa-credit-transfers',9500.00,1700.00;
EXEC sp_insert_transaction 'TX-A04','ACC-001-PRO','LT601010012345678901',        6200.00,'2025-04-21 11:30:00','Règlement solde','instant-sepa-credit-transfers',7000.00, 800.00;
EXEC sp_insert_transaction 'TX-A05','ACC-002-PRO','BE71096123456769',            9400.00,'2025-05-19 13:00:00','Paiement service','sepa-credit-transfers',11000.00,1600.00;
EXEC sp_insert_transaction 'TX-A06','ACC-003-PRO','CY17002001280000001200527600',15000.00,'2025-06-16 14:00:00','Transaction internationale','instant-sepa-credit-transfers',16000.00,1000.00;
EXEC sp_insert_transaction 'TX-A07','ACC-001-PRO','MT84MALT011000012345MTLCAST001S',5800.00,'2025-01-29 15:30:00','Règlement facture','sepa-credit-transfers',6500.00, 700.00;
EXEC sp_insert_transaction 'TX-A08','ACC-002-PRO','FR7630004000039999999999999', 7200.00,'2025-02-24 10:00:00','Paiement urgent','instant-sepa-credit-transfers',8000.00, 800.00;
EXEC sp_insert_transaction 'TX-A09','ACC-003-PRO','GB29NWBK60161331926819',     11500.00,'2025-03-25 11:00:00','Wire transfer','sepa-credit-transfers',13000.00,1500.00;
EXEC sp_insert_transaction 'TX-A10','ACC-001-PRO','DE89370400440532013000',       6900.00,'2025-04-28 14:00:00','Virement pro urgent','sepa-credit-transfers',7500.00, 600.00;


-- ── ANOMALIE TYPE 2 — HORAIRE NOCTURNE ───────────────────────
-- Signal horaire : booking_hour entre 22h et 5h
-- Score attendu : 20 pts → niveau MODÉRÉ (combinable avec d'autres signaux)

EXEC sp_insert_transaction 'TX-B01','ACC-001-PRO','FR7614508711001122334455667',  450.00,'2025-01-23 23:15:00','Virement nuit urgent','sepa-credit-transfers',3000.00,2550.00;
EXEC sp_insert_transaction 'TX-B02','ACC-002-PRO','BE71096123456769',             820.00,'2025-02-12 01:30:00','Règlement nuit','instant-sepa-credit-transfers',5000.00,4180.00;
EXEC sp_insert_transaction 'TX-B03','ACC-003-PRO','FR7630004000039999999999999',  310.00,'2025-03-19 02:45:00','Paiement tardif','sepa-credit-transfers',7000.00,6690.00;
EXEC sp_insert_transaction 'TX-B04','ACC-001-PRO','CY17002001280000001200527600', 680.00,'2025-04-22 22:50:00','Transfer nuit','sepa-credit-transfers',2500.00,1820.00;
EXEC sp_insert_transaction 'TX-B05','ACC-002-PRO','GB29NWBK60161331926819',       920.00,'2025-05-20 03:20:00','Virement nocturne','instant-sepa-credit-transfers',4500.00,3580.00;
EXEC sp_insert_transaction 'TX-B06','ACC-003-PRO','LT601010012345678901',          540.00,'2025-06-17 00:10:00','Transaction nuit','sepa-credit-transfers',6500.00,5960.00;
EXEC sp_insert_transaction 'TX-B07','ACC-001-PRO','MT84MALT011000012345MTLCAST001S',750.00,'2025-01-25 04:30:00','Paiement 4h du matin','sepa-credit-transfers',2800.00,2050.00;
EXEC sp_insert_transaction 'TX-B08','ACC-002-PRO','DE89370400440532013000',        490.00,'2025-02-15 23:55:00','Virement minuit','sepa-credit-transfers',4800.00,4310.00;
EXEC sp_insert_transaction 'TX-B09','ACC-003-PRO','FR7614508711001122334455667',   620.00,'2025-03-22 02:00:00','Règlement nuit 2h','instant-sepa-credit-transfers',6800.00,6180.00;
EXEC sp_insert_transaction 'TX-B10','ACC-001-PRO','BE71096123456769',              380.00,'2025-04-26 05:00:00','Transfer aube','sepa-credit-transfers',2200.00,1820.00;


-- ── ANOMALIE TYPE 3 — BÉNÉFICIAIRE INCONNU + MONTANT > P90 ───
-- Signal bénéficiaire : is_trusted=0 ET montant élevé
-- Score attendu : 25–45 pts → niveau ÉLEVÉ

EXEC sp_insert_transaction 'TX-C01','ACC-001-PRO','FR7614508711001122334455667', 1800.00,'2025-01-24 10:00:00','Prestation conseil','sepa-credit-transfers',5000.00,3200.00;
EXEC sp_insert_transaction 'TX-C02','ACC-002-PRO','BE71096123456769',            2200.00,'2025-02-13 11:30:00','Mission freelance','sepa-credit-transfers',7000.00,4800.00;
EXEC sp_insert_transaction 'TX-C03','ACC-003-PRO','CY17002001280000001200527600',3100.00,'2025-03-20 14:00:00','Règlement prestation','sepa-credit-transfers',8500.00,5400.00;
EXEC sp_insert_transaction 'TX-C04','ACC-001-PRO','LT601010012345678901',         1600.00,'2025-04-23 09:30:00','Paiement service B2B','instant-sepa-credit-transfers',4000.00,2400.00;
EXEC sp_insert_transaction 'TX-C05','ACC-002-PRO','MT84MALT011000012345MTLCAST001S',2800.00,'2025-05-21 10:00:00','Transaction commerciale','sepa-credit-transfers',6500.00,3700.00;
EXEC sp_insert_transaction 'TX-C06','ACC-003-PRO','GB29NWBK60161331926819',      1900.00,'2025-06-18 11:00:00','Règlement international','sepa-credit-transfers',7200.00,5300.00;
EXEC sp_insert_transaction 'TX-C07','ACC-001-PRO','DE89370400440532013000',       2400.00,'2025-01-30 13:00:00','Achat asset','sepa-credit-transfers',4500.00,2100.00;
EXEC sp_insert_transaction 'TX-C08','ACC-002-PRO','FR7630004000039999999999999',  1700.00,'2025-02-25 14:30:00','Virement pro','instant-sepa-credit-transfers',5500.00,3800.00;
EXEC sp_insert_transaction 'TX-C09','ACC-003-PRO','FR7614508711001122334455667',  3400.00,'2025-03-26 10:00:00','Paiement fournisseur','sepa-credit-transfers',8000.00,4600.00;
EXEC sp_insert_transaction 'TX-C10','ACC-001-PRO','BE71096123456769',             2100.00,'2025-04-29 11:30:00','Règlement B2B','sepa-credit-transfers',3500.00,1400.00;


-- ── ANOMALIE TYPE 4 — TENSION DE TRÉSORERIE ──────────────────
-- Signal trésorerie : solde résiduel < 10% du solde avant
-- Score attendu : 15–35 pts → niveau MODÉRÉ à ÉLEVÉ

EXEC sp_insert_transaction 'TX-D01','ACC-001-PRO','FR7614508711001122334455667', 2850.00,'2025-01-27 14:00:00','Vidage compte','sepa-credit-transfers',3000.00, 150.00;
EXEC sp_insert_transaction 'TX-D02','ACC-002-PRO','GB29NWBK60161331926819',      4600.00,'2025-02-17 15:30:00','Transfert total','instant-sepa-credit-transfers',5000.00, 400.00;
EXEC sp_insert_transaction 'TX-D03','ACC-003-PRO','CY17002001280000001200527600',7200.00,'2025-03-24 10:00:00','Règlement solde compte','sepa-credit-transfers',7500.00, 300.00;
EXEC sp_insert_transaction 'TX-D04','ACC-001-PRO','DE89370400440532013000',       1900.00,'2025-04-25 11:00:00','Solde quasi total','sepa-credit-transfers',2000.00, 100.00;
EXEC sp_insert_transaction 'TX-D05','ACC-002-PRO','LT601010012345678901',          3600.00,'2025-05-22 14:00:00','Transfert intégral','instant-sepa-credit-transfers',3800.00, 200.00;
EXEC sp_insert_transaction 'TX-D06','ACC-003-PRO','MT84MALT011000012345MTLCAST001S',6300.00,'2025-06-19 10:30:00','Virement quasi total','sepa-credit-transfers',6500.00, 200.00;
EXEC sp_insert_transaction 'TX-D07','ACC-001-PRO','BE71096123456769',             2700.00,'2025-01-31 13:00:00','Règlement compte','sepa-credit-transfers',2900.00, 200.00;
EXEC sp_insert_transaction 'TX-D08','ACC-002-PRO','FR7630004000039999999999999',  4100.00,'2025-02-26 14:00:00','Transfer solde','sepa-credit-transfers',4400.00, 300.00;
EXEC sp_insert_transaction 'TX-D09','ACC-003-PRO','GB29NWBK60161331926819',       5500.00,'2025-03-27 10:00:00','Virement complet','instant-sepa-credit-transfers',5800.00, 300.00;
EXEC sp_insert_transaction 'TX-D10','ACC-001-PRO','DE89370400440532013000',        1750.00,'2025-04-30 11:30:00','Solde intégral','sepa-credit-transfers',1900.00, 150.00;


-- ── ANOMALIE TYPE 5 — CRITIQUE (multi-signaux combinés) ───────
-- Combinaison : montant élevé + nuit + bénéficiaire inconnu + solde quasi vide
-- Score attendu : 60–100 pts → niveau CRITIQUE

EXEC sp_insert_transaction 'TX-E01','ACC-001-PRO','GB29NWBK60161331926819',      8800.00,'2025-01-28 23:30:00','Virement urgent nuit','instant-sepa-credit-transfers',9500.00, 700.00;
EXEC sp_insert_transaction 'TX-E02','ACC-002-PRO','CY17002001280000001200527600',13500.00,'2025-02-20 01:00:00','Transfert confidentiel nuit','instant-sepa-credit-transfers',14500.00,1000.00;
EXEC sp_insert_transaction 'TX-E03','ACC-003-PRO','LT601010012345678901',          9200.00,'2025-03-23 02:30:00','Wire nocturne','instant-sepa-credit-transfers',9800.00, 600.00;
EXEC sp_insert_transaction 'TX-E04','ACC-001-PRO','MT84MALT011000012345MTLCAST001S',7600.00,'2025-04-24 22:45:00','Paiement nuit casino','instant-sepa-credit-transfers',8000.00, 400.00;
EXEC sp_insert_transaction 'TX-E05','ACC-002-PRO','DE89370400440532013000',       11800.00,'2025-05-23 03:15:00','Transfer nuit grande valeur','instant-sepa-credit-transfers',12500.00, 700.00;
EXEC sp_insert_transaction 'TX-E06','ACC-003-PRO','FR7614508711001122334455667',  16000.00,'2025-06-20 00:30:00','Virement critique nuit','instant-sepa-credit-transfers',16500.00, 500.00;
EXEC sp_insert_transaction 'TX-E07','ACC-001-PRO','BE71096123456769',              6500.00,'2025-01-26 04:00:00','Transaction suspecte aube','instant-sepa-credit-transfers',7000.00, 500.00;
EXEC sp_insert_transaction 'TX-E08','ACC-002-PRO','FR7630004000039999999999999',  10200.00,'2025-02-23 23:00:00','Gros virement nuit','sepa-credit-transfers',11000.00, 800.00;
EXEC sp_insert_transaction 'TX-E09','ACC-003-PRO','CY17002001280000001200527600', 14000.00,'2025-03-21 01:45:00','Wire international nuit','instant-sepa-credit-transfers',14800.00, 800.00;
EXEC sp_insert_transaction 'TX-E10','ACC-001-PRO','GB29NWBK60161331926819',        8100.00,'2025-04-27 02:00:00','Transaction 2h matin','instant-sepa-credit-transfers',8500.00, 400.00;

PRINT '✓ Toutes les transactions insérées (50 normales + 50 anomalies)';
GO

-- PARTIE 5 — CALCUL DU RISK SCORE COMPOSITE
-- Score = somme de 4 signaux pondérés (max 100 pts)
-- Signal 1 : Montant Z-score  → max 40 pts
-- Signal 2 : Horaire atypique → 20 pts fixes
-- Signal 3 : Bénéficiaire inconnu + montant > P90 → 25 pts fixes
-- Signal 4 : Tension trésorerie (solde < 10%) → 15 pts fixes

WITH stats AS (
    -- Moyenne et écart-type par compte (pour Z-score)
    SELECT
        account_id,
        AVG(amount_eur)   AS avg_amt,
        STDEV(amount_eur) AS std_amt
    FROM fact_transactions
    WHERE direction = 'DEBIT'
    GROUP BY account_id
),
p90 AS (
    -- 90ème percentile par compte (pour signal bénéficiaire)
    SELECT DISTINCT
        account_id,
        PERCENTILE_CONT(0.90)
            WITHIN GROUP (ORDER BY amount_eur)
            OVER (PARTITION BY account_id) AS p90_amount
    FROM fact_transactions
    WHERE direction = 'DEBIT'
),
scored AS (
    SELECT
        ft.transaction_id,

        -- SIGNAL 1 : Z-score montant (plafonné à 40 pts)
        CASE
            WHEN s.std_amt > 0
            THEN ROUND(
                    CASE
                        WHEN ((ft.amount_eur - s.avg_amt) / s.std_amt) * 10 > 40
                        THEN 40.0
                        ELSE ((ft.amount_eur - s.avg_amt) / s.std_amt) * 10
                    END, 1)
            ELSE 0
        END
        -- SIGNAL 2 : Horaire nocturne ou weekend (20 pts)
        + CASE
            WHEN dd.booking_hour NOT BETWEEN 6 AND 21
              OR dd.is_weekend = 1
            THEN 20.0
            ELSE 0.0
          END
        -- SIGNAL 3 : Bénéficiaire inconnu + montant > P90 (25 pts)
        + CASE
            WHEN db.is_trusted = 0
             AND ft.amount_eur > p.p90_amount
            THEN 25.0
            ELSE 0.0
          END
        -- SIGNAL 4 : Tension trésorerie (15 pts)
        + CASE
            WHEN ft.balance_before > 0
             AND (ft.balance_after / ft.balance_before) < 0.10
            THEN 15.0
            ELSE 0.0
          END
        AS risk_score

    FROM fact_transactions ft
    JOIN dim_date        dd ON ft.date_id        = dd.date_id
    JOIN dim_beneficiary db ON ft.beneficiary_id = db.beneficiary_id
    JOIN stats           s  ON ft.account_id     = s.account_id
    JOIN p90             p  ON ft.account_id     = p.account_id
    WHERE ft.direction = 'DEBIT'
)
UPDATE ft
SET
    ft.risk_score = ROUND(CASE WHEN s.risk_score < 0 THEN 0 ELSE s.risk_score END, 1),
    ft.is_anomaly = CASE WHEN s.risk_score >= 35 THEN 1 ELSE 0 END
FROM fact_transactions ft
JOIN scored s ON ft.transaction_id = s.transaction_id;

PRINT '✓ Risk scores calculés et mis à jour';
GO

-- PARTIE 6 — VUE ANALYTIQUE POUR POWER BI


CREATE OR ALTER VIEW vw_risk_dashboard AS
SELECT
    ft.transaction_id,
    ft.sg_transaction_id,

    -- Compte
    da.iban                 AS compte_iban,
    da.account_name,

    -- Bénéficiaire
    db.creditor_name,
    db.creditor_iban,
    db.country_code,
    db.is_trusted,

    -- Montants et soldes
    ft.amount_eur,
    ft.balance_before,
    ft.balance_after,
    CASE
        WHEN ft.balance_before > 0
        THEN ROUND((ft.balance_after / ft.balance_before) * 100, 1)
        ELSE NULL
    END                     AS pct_solde_restant,

    -- Temporel
    dd.booking_date,
    dd.booking_day,
    dd.booking_hour,
    dd.day_of_week,
    dd.is_weekend,
    dd.month_num,
    dd.year_num,

    -- Produit et motif
    ft.payment_product,
    ft.remittance_info,
    ft.direction,

    -- Score et niveau
    ft.risk_score,
    ft.is_anomaly,
    CASE
        WHEN ft.risk_score >= 60 THEN 'CRITIQUE'
        WHEN ft.risk_score >= 35 THEN 'ÉLEVÉ'
        WHEN ft.risk_score >= 15 THEN 'MODÉRÉ'
        ELSE 'NORMAL'
    END                     AS risk_level,

    -- Ordre pour tri Power BI (1=NORMALE ... 4=CRITIQUE)
    CASE
        WHEN ft.risk_score >= 60 THEN 4
        WHEN ft.risk_score >= 35 THEN 3
        WHEN ft.risk_score >= 15 THEN 2
        ELSE 1
    END                     AS risk_order

FROM fact_transactions ft
JOIN dim_account     da ON ft.account_id     = da.account_id
JOIN dim_beneficiary db ON ft.beneficiary_id = db.beneficiary_id
JOIN dim_date        dd ON ft.date_id        = dd.date_id;
GO


-- PARTIE 7 — VÉRIFICATION RAPIDE 


-- Résumé par niveau de risque
SELECT
    CASE
        WHEN risk_score >= 60 THEN 'CRITIQUE'
        WHEN risk_score >= 35 THEN 'ÉLEVÉ'
        WHEN risk_score >= 15 THEN 'MODÉRÉ'
        ELSE 'NORMAL'
    END                         AS niveau,
    COUNT(*)                    AS nb_transactions,
    ROUND(AVG(risk_score), 1)   AS score_moyen,
    ROUND(SUM(amount_eur), 2)   AS montant_total_eur
FROM fact_transactions
WHERE direction = 'DEBIT'
GROUP BY
    CASE
        WHEN risk_score >= 60 THEN 'CRITIQUE'
        WHEN risk_score >= 35 THEN 'ÉLEVÉ'
        WHEN risk_score >= 15 THEN 'MODÉRÉ'
        ELSE 'NORMAL'
    END
ORDER BY score_moyen DESC;

-- Aperçu des 10 transactions les plus suspectes
SELECT TOP 10
    sg_transaction_id,
    amount_eur,
    risk_score,
    CASE
        WHEN risk_score >= 60 THEN 'CRITIQUE'
        WHEN risk_score >= 35 THEN 'ÉLEVÉ'
        ELSE 'MODÉRÉ'
    END AS niveau,
    remittance_info
FROM fact_transactions
WHERE direction = 'DEBIT'
ORDER BY risk_score DESC;
GO
