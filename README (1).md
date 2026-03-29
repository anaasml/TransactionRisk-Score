# TransactionRisk Score

Projet de détection d'anomalies sur des transactions bancaires, réalisé avec SQL Server et Power BI.

L'idée de base c'est simple : les banques traitent des milliers de virements par jour et certains sont frauduleux. Plutôt que de bloquer tout ce qui dépasse un seuil fixe, j'ai construit un score de risque (0 à 100) qui combine plusieurs signaux pour classer chaque transaction en 4 niveaux : NORMAL, MODÉRÉ, ÉLEVÉ, CRITIQUE.

Les données sont simulées au format réel de l'API DSP2 de la Société Générale (Berlin Group NextGenPSD2).

---

## Stack

- SQL Server / SSMS
- Power BI Desktop
- T-SQL (window functions, CTEs, procédures stockées)

---

## Structure du projet

```
TransactionRisk-Score/
├── sql/
│   └── TransactionRisk_FULL.sql
├── screenshots/
│   ├── page1_vue_ensemble.png
│   ├── page2_temporel.png
│   └── page3_detail.png
└── README.md
```

---

## Modèle de données

Star schema avec 5 tables :

- `fact_transactions` — une ligne par virement, avec le risk score calculé
- `dim_account` — les comptes bancaires
- `dim_beneficiary` — les bénéficiaires (trusted ou non)
- `dim_date` — dates avec features temporelles (heure, jour semaine, weekend)
- `dim_balance` — snapshots de solde avant/après virement

---

## Logique du score

Le score est la somme de 4 signaux :

**Signal 1 — Montant anormal (max 40 pts)**
Je calcule le Z-score de chaque transaction par rapport à l'historique du compte. Un Z > 3 signifie que ce montant arrive moins de 0,3% du temps — c'est statistiquement exceptionnel.

**Signal 2 — Horaire atypique (20 pts)**
Les virements entre 22h et 6h ou le weekend sont flaggés. Les fraudes arrivent souvent la nuit quand les équipes de surveillance sont réduites.

**Signal 3 — Bénéficiaire inconnu + montant élevé (25 pts)**
Un gros virement vers quelqu'un qu'on n'a jamais payé avant. La combinaison des deux est ce qui rend ça suspect — un petit virement vers un inconnu c'est normal, un gros c'est une autre histoire.

**Signal 4 — Tension de trésorerie (15 pts)**
Si le solde après virement représente moins de 10% du solde avant, le compte a été quasi vidé d'un coup.

| Score | Niveau | Action |
|-------|--------|--------|
| 0–14 | NORMAL | Rien |
| 15–34 | MODÉRÉ | Surveillance |
| 35–59 | ÉLEVÉ | Alerte conformité |
| 60–100 | CRITIQUE | Blocage préventif |

---

## Résultats sur les données simulées

Sur 100 transactions :
- 9 CRITIQUE — score moyen 80 — 103 300€ exposés
- 10 ÉLEVÉ — score moyen 43
- 12 MODÉRÉ — score moyen 17
- 69 NORMAL

---

## Dashboard Power BI

3 pages :
- Vue d'ensemble avec les KPI principaux et l'évolution du score dans le temps
- Analyse temporelle — volume par heure et répartition weekend/semaine
- Table de détail avec mise en forme conditionnelle sur le score

---

## Comment lancer le projet

1. Ouvrir SSMS et créer une base `TransactionRiskDB`
2. Exécuter `TransactionRisk_FULL.sql` (F5)
3. Ouvrir Power BI Desktop
4. Obtenir des données → SQL Server → `localhost\SQLEXPRESS` → `TransactionRiskDB` → vue `vw_risk_dashboard`
