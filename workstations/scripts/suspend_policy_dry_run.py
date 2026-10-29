#!/usr/bin/env python3
"""Fail-closed, side-effect-free admission model; NEVER calls a cloud API.

This is NOT a controller and never grants permission to suspend a VM.
A true verdict means only that an independently authorized controller
may attempt a FINAL transactional recheck.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime
from decimal import Decimal
from zoneinfo import ZoneInfo

BAHIA = ZoneInfo("America/Bahia")
VETO_WINDOW_SECONDS = 3600
IDLE_WINDOW_SECONDS = 7200  # candidate threshold, not production approval
MAX_OBSERVATION_AGE_SECONDS = 60  # candidate bound; stale = no suspend
BUDGET_BRL = Decimal("400")


@dataclass(frozen=True)
class TrustedConfig:
    project: str
    zone: str
    instance: str
    instance_id: str
    budget_id: str
    billing_account_id: str


@dataclass(frozen=True)
class VetoLedgerRead:
    """Simulated authoritative snapshot; NOT an authenticated store client.

    Production must produce this proof in a transaction with the final
    permission check, not from a cached message consumer or Pub/Sub cursor.
    committed_sequence is the durable producer watermark; contiguous_sequence
    is the consumer's gap-free applied prefix.
    """
    proposal_id: str
    reason: str
    month: str | None
    generation: int
    read_at_s: int
    committed_sequence: int
    contiguous_sequence: int
    source_verified: bool = False
    integrity_ok: bool = False
    vetoed: bool = True
    closed: bool = True


@dataclass(frozen=True)
class Candidate:
    project: str = "argon-surf-472319-b0"
    zone: str = "southamerica-east1-b"
    instance: str = "wsklarkc"
    instance_id: str = ""
    vm_status: str = "RUNNING"
    reason: str = "idle"
    proposal_id: str = ""
    proposal_open: bool = False
    observed_at_s: int | None = None
    now_s: int = 1_790_000_000
    proposal_generation: int = 1
    live_generation: int = 1
    resume_in_progress: bool | None = None
    human_state: str = "unknown"
    work_state: str = "unknown"
    resources_state: str = "unknown"
    human_idle_since_s: int | None = None
    resources_idle_since_s: int | None = None
    other_session_active: bool | None = None
    email_state: str = "unknown"
    email_provider_id: str | None = None
    email_accepted_at_s: int | None = None
    email_recipient_verified: bool = False
    proposal_created_at_s: int | None = None
    graphical_session_connected: bool | None = None
    graphical_notice_confirmed: bool = False
    vetoed_proposal: bool = False
    veto_state_fresh: bool = False
    veto_ledger_read: VetoLedgerRead | None = None
    idle_vetoed_proposals: frozenset[str] = frozenset()
    budget_vetoed_month: str | None = None
    budget_id: str | None = None
    budget_currency: str | None = None
    billing_account_id: str | None = None
    budget_scope: str | None = None
    budget_source_verified: bool = False
    budget_kind: str | None = None
    budget_period: str | None = None
    cost_amount_brl: Decimal | None = None
    budget_amount_brl: Decimal | None = None


@dataclass(frozen=True)
class Verdict:
    eligible_for_final_recheck: bool
    reason: str


def _fail(reason: str) -> Verdict:
    return Verdict(False, reason)


def current_month(now_s: int) -> str:
    return datetime.fromtimestamp(now_s, BAHIA).strftime("%Y-%m")


def evaluate(c: Candidate, config: TrustedConfig) -> Verdict:
    """Offline dry-run only: unknown, missing, stale or unsafe => DENY."""
    if (
        not config.project or not config.zone or not config.instance
        or not config.instance_id or c.project != config.project
        or c.zone != config.zone or c.instance != config.instance
        or c.instance_id != config.instance_id
    ):
        return _fail("vm_not_allowlisted")
    if c.vm_status != "RUNNING":
        return _fail("vm_not_running")
    if c.reason not in {"idle", "budget"} or not c.proposal_id or not c.proposal_open:
        return _fail("invalid_or_closed_proposal")
    if c.resume_in_progress is not False or c.proposal_generation != c.live_generation:
        return _fail("resume_or_generation_changed")
    if c.observed_at_s is None or c.now_s < 0 or not (
        0 <= c.now_s - c.observed_at_s <= MAX_OBSERVATION_AGE_SECONDS
    ):
        return _fail("no_fresh_evidence")
    if c.other_session_active is not False:
        return _fail("another_session_active")
    if c.human_state != "idle" or c.work_state != "idle" or c.resources_state != "idle":
        return _fail("human_work_or_resources_not_proven_idle")
    if not c.veto_state_fresh:
        return _fail("veto_state_not_verified")
    if c.vetoed_proposal:
        return _fail("proposal_vetoed")
    ledger = c.veto_ledger_read
    required_month = current_month(c.now_s) if c.reason == "budget" else None
    if (
        ledger is None or ledger.source_verified is not True
        or ledger.integrity_ok is not True
        or ledger.proposal_id != c.proposal_id
        or ledger.reason != c.reason
        or ledger.month != required_month
        or ledger.generation != c.live_generation
        or ledger.vetoed is not False or ledger.closed is not False
        or not isinstance(ledger.committed_sequence, int)
        or isinstance(ledger.committed_sequence, bool)
        or ledger.committed_sequence < 1
        or ledger.contiguous_sequence != ledger.committed_sequence
        or ledger.read_at_s < c.observed_at_s
        or not (0 <= c.now_s - ledger.read_at_s <= MAX_OBSERVATION_AGE_SECONDS)
    ):
        # No gaps or unknown delayed veto may be silently treated as a NO.
        # This is still only an ADMISSION to a final transactional recheck.
        return _fail("veto_ledger_unavailable_or_not_gap_free")
    if c.reason == "idle":
        if c.proposal_id in c.idle_vetoed_proposals:
            return _fail("idle_proposal_vetoed")
        if c.human_idle_since_s is None or c.resources_idle_since_s is None or (
            c.human_idle_since_s > c.now_s - IDLE_WINDOW_SECONDS
            or c.resources_idle_since_s > c.now_s - IDLE_WINDOW_SECONDS
        ):
            return _fail("idle_window_not_proven")
    else:
        month = current_month(c.now_s)
        if c.budget_vetoed_month == month:
            return _fail("budget_cycle_vetoed")
        if (
            not c.budget_id or not config.budget_id or not config.billing_account_id
            or c.budget_id != config.budget_id
            or c.billing_account_id != config.billing_account_id
            or c.budget_scope != "billing_account"
            or c.budget_source_verified is not True
            or c.budget_currency != "BRL" or c.budget_kind != "actual"
            or c.budget_period != month
            or not isinstance(c.cost_amount_brl, Decimal)
            or not isinstance(c.budget_amount_brl, Decimal)
            or not c.cost_amount_brl.is_finite()
            or not c.budget_amount_brl.is_finite()
            or c.budget_amount_brl != BUDGET_BRL
            or c.cost_amount_brl <= c.budget_amount_brl
        ):
            return _fail("budget_event_not_verified_above_limit")
    if (
        c.email_state != "accepted" or not c.email_provider_id
        or not c.email_recipient_verified or c.email_accepted_at_s is None
        or c.proposal_created_at_s is None
        or not (0 <= c.proposal_created_at_s <= c.email_accepted_at_s <= c.now_s)
    ):
        return _fail("email_acceptance_not_verified")
    if c.graphical_session_connected is None:
        return _fail("graphical_session_state_unknown")
    if c.graphical_session_connected and not c.graphical_notice_confirmed:
        return _fail("graphical_notice_not_confirmed")
    if c.reason == "budget" and (
        current_month(c.proposal_created_at_s) != current_month(c.now_s)
        or current_month(c.email_accepted_at_s) != current_month(c.now_s)
    ):
        return _fail("budget_notice_from_other_month")
    if c.now_s - c.email_accepted_at_s < VETO_WINDOW_SECONDS:
        return _fail("veto_window_open")
    # A final recheck in the outside, durable controller is still mandatory.
    return Verdict(True, "requires_final_transactional_recheck")


@dataclass(frozen=True)
class ProposalLedger:
    """Pure single-proposal snapshot; production needs durable transactions."""
    proposal_id: str
    reason: str
    month: str | None
    generation: int
    last_sequence: int = 0
    processed_ids: frozenset[str] = frozenset()
    processed_sequences: frozenset[int] = frozenset()
    integrity_failed: bool = False
    email_accepted_at_s: int | None = None
    email_provider_id: str | None = None
    vetoed: bool = False
    closed: bool = False


@dataclass(frozen=True)
class ProposalEvent:
    event_id: str
    proposal_id: str
    reason: str
    month: str | None
    generation: int
    sequence: int
    event_type: str  # provider_accepted | veto | close | resume
    timestamp_s: int
    # These booleans simulate an independently authenticated service result.
    source_authenticated: bool = False
    recipient_verified: bool = False
    email_provider_id: str | None = None


def reduce_proposal_event(state: ProposalLedger, event: ProposalEvent) -> ProposalLedger:
    """Offline monotonic tombstones plus contiguous-prefix accounting.

    This function has NO transaction, durable storage, API or authorization.
    An authoritative transaction must expose a COMMITTED sequence watermark
    and guarantee that every sequence through that watermark was processed.
    Delayed veto/resume/close MUST NOT be dropped on arrival.
    """
    if (
        state.closed or not event.event_id or not event.source_authenticated
        or not state.proposal_id or state.reason not in {"idle", "budget"}
        or event.proposal_id != state.proposal_id or event.reason != state.reason
        or event.month != state.month or event.generation != state.generation
        or not isinstance(event.sequence, int) or isinstance(event.sequence, bool)
        or event.sequence < 1 or event.event_id in state.processed_ids
        or event.timestamp_s < 0 or event.event_type not in {
            "provider_accepted", "veto", "close", "resume"
        }
    ):
        return state

    # A different event ID reusing an already-applied sequence means the
    # producer's identity/ordering invariant was violated: fail closed.
    if event.sequence in state.processed_sequences:
        return replace(
            state, integrity_failed=True,
            vetoed=state.vetoed or event.event_type == "veto",
            closed=state.closed or event.event_type in {"close", "resume"},
        )

    # Never accept an unverified receipt and advance the gap-free cursor.
    if event.event_type == "provider_accepted" and (
        not event.recipient_verified or not event.email_provider_id
    ):
        return state

    applied = state.processed_sequences | {event.sequence}
    prefix = state.last_sequence
    while prefix + 1 in applied:
        prefix += 1
    fields = {
        "last_sequence": prefix,
        "processed_ids": state.processed_ids | {event.event_id},
        "processed_sequences": applied,
    }
    if event.event_type == "provider_accepted":
        if state.email_accepted_at_s is None:
            # First PROCESSED provider receipt is conservative: a delayed
            # older receipt must never retroactively shorten the veto window.
            fields.update(email_accepted_at_s=event.timestamp_s,
                          email_provider_id=event.email_provider_id)
    elif event.event_type == "veto":
        # Monotonic tombstone, even when event.sequence < highest received.
        fields["vetoed"] = True
    elif event.event_type in {"close", "resume"}:
        fields["closed"] = True
    return replace(state, **fields)
