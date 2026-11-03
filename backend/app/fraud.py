from dataclasses import dataclass
import numpy as np
from sklearn.ensemble import IsolationForest

@dataclass(frozen=True)
class RiskAssessment:
    score: int
    model_score: int
    level: str
    action: str
    reasons: list[str]

class FraudScorer:
    """Real AI Mode: Uses Isolation Forest for anomaly detection."""

    def __init__(self) -> None:
        # Generate synthetic 'normal' training data
        rng = np.random.default_rng(2026)
        samples = np.column_stack(
            (
                np.log1p(rng.lognormal(mean=7.2, sigma=1.15, size=1000)),
                rng.integers(0, 3650, size=1000),
                rng.poisson(lam=2.5, size=1000),
                rng.integers(0, 24, size=1000),
                rng.binomial(1, 0.02, size=1000),
                rng.binomial(1, 0.15, size=1000),
            )
        )
        self.model = IsolationForest(
            n_estimators=100,
            contamination=0.03,
            random_state=2026,
        ).fit(samples)
        
        scores = self.model.score_samples(samples)
        self.lower_bound = float(np.quantile(scores, 0.01))
        self.upper_bound = float(np.quantile(scores, 0.99))

    def assess(
        self,
        amount: float,
        hour: int,
        account_age_days: int,
        transactions_24h: int,
        new_recipient: bool,
        sim_changed: bool,
    ) -> RiskAssessment:
        rule_score = 0
        reasons: list[str] = []

        def add(points: int, reason: str) -> None:
            nonlocal rule_score
            rule_score += points
            reasons.append(reason)

        # Base Rules
        if amount >= 50_000: add(25, "High amount (>= ETB 50,000)")
        if account_age_days < 7 and amount >= 10_000: add(25, "New account with large transfer")
        if hour < 5 or hour >= 23: add(10, "Night-time activity")
        if transactions_24h >= 10: add(20, "High velocity: 10+ transfers in 24h")
        if sim_changed and amount >= 5_000: add(30, "Recent SIM change + sizeable transfer")

        # AI Anomaly Detection
        features = np.array([[
            np.log1p(amount), account_age_days, transactions_24h, hour,
            int(sim_changed), int(new_recipient)
        ]])
        raw_score = float(self.model.score_samples(features)[0])
        span = max(self.upper_bound - self.lower_bound, 1e-6)
        model_score = round(100 * np.clip((self.upper_bound - raw_score) / span, 0, 1))
        
        # Combine AI and Rules
        score = min(100, max(rule_score, round(model_score * 0.7)))
        if model_score >= 70:
            reasons.append(f"AI Detection: Unusual transaction pattern ({model_score}/100)")

        level = "low" if score < 30 else "medium" if score < 60 else "high"
        action = "allow" if score < 30 else "step_up" if score < 60 else "hold" if score < 80 else "block"
        return RiskAssessment(score, model_score, level, action, reasons)

fraud_scorer = FraudScorer()
