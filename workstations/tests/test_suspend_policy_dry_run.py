"""No-network, deterministic-time regressions for GCE suspend policy."""
from dataclasses import replace
from itertools import permutations
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from suspend_policy_dry_run import (  # noqa: E402
    Candidate, ProposalEvent, ProposalLedger, TrustedConfig, VetoLedgerRead,
    current_month, evaluate, reduce_proposal_event,
)

NOW = 1_793_311_200  # 2026-10-29 19:00 America/Bahia
CONFIG = TrustedConfig(
    project="argon-surf-472319-b0", zone="southamerica-east1-b",
    instance="wsklarkc", instance_id="test-instance-id",
    budget_id="configured-budget-id", billing_account_id="test-billing-account"
)


def check(c):
    return evaluate(c, CONFIG)


def eligible(reason="idle"):
    common = dict(
        now_s=NOW, instance_id="test-instance-id",
        proposal_id="proposal-test", proposal_open=True,
        resume_in_progress=False, other_session_active=False,
        veto_state_fresh=True, graphical_session_connected=False,
        veto_ledger_read=VetoLedgerRead(
            project="argon-surf-472319-b0", zone="southamerica-east1-b",
            instance_id="test-instance-id",
            proposal_id="proposal-test", reason=reason,
            month=current_month(NOW) if reason == "budget" else None,
            generation=1, read_at_s=NOW, committed_sequence=1,
            contiguous_sequence=1, source_verified=True,
            integrity_ok=True, vetoed=False, closed=False,
        ),
        human_state="idle", work_state="idle", resources_state="idle",
        email_state="accepted", email_provider_id="provider-msg-test",
        email_recipient_verified=True, observed_at_s=NOW,
        human_idle_since_s=NOW - 8000, resources_idle_since_s=NOW - 8000,
        proposal_created_at_s=NOW - 5000, email_accepted_at_s=NOW - 3600,
        reason=reason,
    )
    if reason == "budget":
        common.update(
            budget_id="configured-budget-id", budget_currency="BRL",
            billing_account_id="test-billing-account", budget_scope="billing_account",
            budget_source_verified=True, budget_kind="actual",
            budget_period=current_month(NOW), cost_amount_brl=Decimal("400.01"),
            budget_amount_brl=Decimal("400"),
        )
    return Candidate(**common)


class SuspendAdmissionTests(unittest.TestCase):
    def test_default_unknown_never_eligible(self):
        self.assertFalse(check(Candidate()).eligible_for_final_recheck)

    def test_veto_boundary_at_3599_and_3600_both_policies(self):
        for reason in ("idle", "budget"):
            with self.subTest(reason=reason):
                c = eligible(reason)
                self.assertFalse(check(replace(c, email_accepted_at_s=NOW - 3599)).eligible_for_final_recheck)
                self.assertEqual(check(c).reason, "requires_final_transactional_recheck")
                self.assertTrue(check(c).eligible_for_final_recheck)

    def test_email_acceptance_status_timestamp_provenance_required(self):
        c = eligible()
        for changes in (
            {"email_state": "unknown"}, {"email_state": "rejected"},
            {"email_accepted_at_s": None}, {"email_provider_id": None},
            {"email_recipient_verified": False}, {"proposal_created_at_s": None},
            {"email_accepted_at_s": NOW + 1}, {"email_accepted_at_s": NOW - 6000},
        ):
            with self.subTest(changes=changes):
                self.assertFalse(check(replace(c, **changes)).eligible_for_final_recheck)

    def test_active_unknown_or_stale_evidence_fails_closed(self):
        c = eligible("budget")
        for state in ("active", "unknown"):
            for attr in ("human_state", "work_state", "resources_state"):
                self.assertFalse(check(replace(c, **{attr: state})).eligible_for_final_recheck)
        for changes in (
            {"observed_at_s": None}, {"observed_at_s": NOW - 61},
            {"observed_at_s": NOW + 1}, {"other_session_active": True},
        ):
            self.assertFalse(check(replace(c, **changes)).eligible_for_final_recheck)

    def test_idle_requires_both_full_two_hour_windows(self):
        c = eligible()
        for changes in (
            {"human_idle_since_s": None}, {"resources_idle_since_s": None},
            {"human_idle_since_s": NOW - 7199},
            {"resources_idle_since_s": NOW - 7199},
        ):
            self.assertFalse(check(replace(c, **changes)).eligible_for_final_recheck)
        self.assertTrue(check(replace(c, human_idle_since_s=NOW - 7200,
                                          resources_idle_since_s=NOW - 7200)).eligible_for_final_recheck)

    def test_budget_only_actual_strict_greater_than_400(self):
        c = eligible("budget")
        for value in (Decimal("399.99"), Decimal("400")):
            self.assertFalse(check(replace(c, cost_amount_brl=value)).eligible_for_final_recheck)
        self.assertTrue(check(replace(c, cost_amount_brl=Decimal("400.0001"))).eligible_for_final_recheck)
        for changes in (
            {"budget_kind": "forecast"}, {"budget_currency": "USD"},
            {"budget_period": "2026-09"}, {"budget_id": "unknown"},
            {"billing_account_id": "wrong"}, {"budget_source_verified": False},
            {"budget_scope": "project"}, {"budget_amount_brl": Decimal("399")},
            {"cost_amount_brl": None}, {"cost_amount_brl": 401.0},
            {"cost_amount_brl": Decimal("NaN")},
        ):
            with self.subTest(changes=changes):
                self.assertFalse(check(replace(c, **changes)).eligible_for_final_recheck)

    def test_veto_scopes_separate(self):
        i,b = eligible(),eligible("budget")
        self.assertFalse(check(replace(i, idle_vetoed_proposals=frozenset({i.proposal_id}))).eligible_for_final_recheck)
        self.assertTrue(check(replace(b, idle_vetoed_proposals=frozenset({i.proposal_id}))).eligible_for_final_recheck)
        self.assertFalse(check(replace(b, budget_vetoed_month=current_month(NOW))).eligible_for_final_recheck)
        self.assertTrue(check(replace(i, budget_vetoed_month=current_month(NOW))).eligible_for_final_recheck)

    def test_last_second_veto_blocks_later_attempt(self):
        for reason in ("idle", "budget"):
            c = eligible(reason)
            self.assertFalse(check(replace(c, vetoed_proposal=True)).eligible_for_final_recheck)
            self.assertFalse(check(replace(c, now_s=NOW+1, observed_at_s=NOW+1,
                                            vetoed_proposal=True)).eligible_for_final_recheck)

    def test_generation_resume_status_or_identity_mismatch(self):
        c = eligible()
        for changes in (
            {"resume_in_progress": True}, {"live_generation": 2},
            {"vm_status": "SUSPENDED"}, {"vm_status": "TERMINATED"},
            {"instance_id": "replaced"}, {"instance": "another-vm"},
        ):
            self.assertFalse(check(replace(c, **changes)).eligible_for_final_recheck)

    def test_unknown_ui_and_veto_state_prohibit_suspension(self):
        c = eligible()
        for changes in (
            {"resume_in_progress": None}, {"other_session_active": None},
            {"veto_state_fresh": False}, {"graphical_session_connected": None},
        ):
            self.assertFalse(check(replace(c, **changes)).eligible_for_final_recheck)

    def test_connected_graphical_session_requires_confirmed_notice(self):
        c = eligible()
        self.assertFalse(check(replace(c, graphical_session_connected=True)).eligible_for_final_recheck)
        self.assertTrue(check(replace(c, graphical_session_connected=True,
                                          graphical_notice_confirmed=True)).eligible_for_final_recheck)

    def test_authoritative_ledger_read_and_gap_free_barrier(self):
        for reason in ("idle", "budget"):
            c = eligible(reason)
            ledger = c.veto_ledger_read
            for bad in (
                None,
                replace(ledger, source_verified=False),
                replace(ledger, integrity_ok=False),
                replace(ledger, proposal_id="other"),
                replace(ledger, project="different-project"),
                replace(ledger, zone="different-zone"),
                replace(ledger, instance_id="different-vm-id"),
                replace(ledger, reason="budget" if reason == "idle" else "idle"),
                replace(ledger, generation=2),
                replace(ledger, month="2026-11"),
                replace(ledger, read_at_s=NOW-61),
                replace(ledger, read_at_s=NOW+1),
                replace(ledger, committed_sequence=2),
                replace(ledger, committed_sequence=True),
                replace(ledger, contiguous_sequence=0),
                replace(ledger, contiguous_sequence=True),
                replace(ledger, read_at_s=True),
                replace(ledger, vetoed=True),
                replace(ledger, closed=True),
            ):
                with self.subTest(reason=reason, bad=bad):
                    self.assertFalse(
                        check(replace(c, veto_ledger_read=bad)).eligible_for_final_recheck
                    )

    def test_ledger_read_must_follow_activity_observation(self):
        c = eligible()
        old = replace(c.veto_ledger_read, read_at_s=NOW-1)
        self.assertFalse(check(replace(c, veto_ledger_read=old)).eligible_for_final_recheck)

    def test_budget_month_rollover_rejects_old_notice(self):
        nov = int(datetime(2026,11,1,0,0,tzinfo=ZoneInfo("America/Bahia")).timestamp())
        c = replace(eligible("budget"), now_s=nov, observed_at_s=nov,
                    email_accepted_at_s=nov-3600, proposal_created_at_s=nov-5000,
                    budget_period="2026-10")
        self.assertFalse(check(c).eligible_for_final_recheck)
        self.assertEqual(current_month(nov), "2026-11")


class ReplayReducerTests(unittest.TestCase):
    def state(self):
        return ProposalLedger(proposal_id="proposal-test", reason="idle", month=None,
                              generation=1)

    def event(self, kind, seq, at=NOW-3600):
        return ProposalEvent(
            event_id=f"event-{seq}", proposal_id="proposal-test", reason="idle",
            month=None, generation=1, sequence=seq, event_type=kind,
            timestamp_s=at, source_authenticated=True, recipient_verified=True,
            email_provider_id="provider-001",
        )

    def test_duplicate_out_of_order_and_replayed_event_ignored(self):
        s=reduce_proposal_event(self.state(),self.event("provider_accepted",2))
        self.assertEqual(s.email_accepted_at_s,NOW-3600)
        self.assertEqual(reduce_proposal_event(s,self.event("provider_accepted",2)),s)
        self.assertEqual(s.last_sequence, 0)  # sequence 1 still missing
        filled = reduce_proposal_event(s, self.event("provider_accepted", 1))
        self.assertEqual(filled.last_sequence, 2)
        self.assertEqual(filled.email_accepted_at_s, NOW-3600)
        self.assertEqual(reduce_proposal_event(s,replace(self.event("veto",3),event_id="event-2")),s)

    def test_late_veto_with_lower_sequence_must_still_block(self):
        s = reduce_proposal_event(self.state(), self.event("provider_accepted", 3))
        veto = replace(self.event("veto", 2, at=NOW-1), event_id="late-veto")
        s = reduce_proposal_event(s, veto)
        self.assertTrue(s.vetoed)
        self.assertEqual(s.last_sequence, 0)  # still missing sequence 1
        s = reduce_proposal_event(s, self.event("provider_accepted", 1))
        self.assertEqual(s.last_sequence, 3)
        self.assertEqual(reduce_proposal_event(s, veto), s)
        c = replace(eligible(), vetoed_proposal=s.vetoed)
        self.assertFalse(check(c).eligible_for_final_recheck)

    def test_out_of_order_close_and_resume_invalidate_proposal(self):
        for event_type in ("close", "resume"):
            s = reduce_proposal_event(self.state(), self.event("provider_accepted", 4))
            later = replace(self.event(event_type, 2), event_id="late-" + event_type)
            s = reduce_proposal_event(s, later)
            self.assertTrue(s.closed)
            self.assertEqual(s.last_sequence, 0)  # missing sequences 1 and 3
            self.assertEqual(reduce_proposal_event(s, self.event("provider_accepted", 5)), s)

    def test_reject_invalid_sequence_even_on_safety_events(self):
        for sequence in (0, -1, True):
            event = replace(self.event("veto", 1), sequence=sequence)
            self.assertEqual(reduce_proposal_event(self.state(), event), self.state())

    def test_seq2_receipt_before_seq1_veto_denies_before_and_after_delivery(self):
        s = reduce_proposal_event(self.state(), self.event("provider_accepted", 2))
        self.assertEqual(s.last_sequence, 0)
        self.assertEqual(s.processed_sequences, frozenset({2}))
        c = eligible()
        gap = replace(c.veto_ledger_read, committed_sequence=2,
                      contiguous_sequence=s.last_sequence, vetoed=s.vetoed)
        self.assertFalse(check(replace(c, veto_ledger_read=gap)).eligible_for_final_recheck)
        s = reduce_proposal_event(s, self.event("veto", 1))
        self.assertEqual(s.last_sequence, 2)
        self.assertTrue(s.vetoed)
        complete = replace(gap, contiguous_sequence=2, vetoed=s.vetoed)
        self.assertFalse(check(replace(c, veto_ledger_read=complete)).eligible_for_final_recheck)

    def test_veto_precedes_provider_receipt_and_remains_irrevocable(self):
        s = reduce_proposal_event(self.state(), self.event("veto", 1, at=NOW-4000))
        self.assertTrue(s.vetoed)
        s = reduce_proposal_event(s, self.event("provider_accepted", 2))
        self.assertEqual(s.last_sequence, 2)
        self.assertTrue(s.vetoed)
        c = eligible()
        snapshot = replace(c.veto_ledger_read, committed_sequence=2,
                           contiguous_sequence=2, vetoed=s.vetoed)
        self.assertFalse(check(replace(c, veto_ledger_read=snapshot)).eligible_for_final_recheck)

    def test_unknown_committed_gap_without_veto_still_denies(self):
        s = reduce_proposal_event(self.state(), self.event("provider_accepted", 3))
        self.assertEqual(s.last_sequence, 0)
        c = eligible()
        snapshot = replace(c.veto_ledger_read, committed_sequence=3,
                           contiguous_sequence=s.last_sequence)
        self.assertFalse(check(replace(c, veto_ledger_read=snapshot)).eligible_for_final_recheck)

    def test_duplicate_sequence_conflict_fails_closed(self):
        s = reduce_proposal_event(self.state(), self.event("provider_accepted", 1))
        conflicting = replace(self.event("veto", 1), event_id="new-event-same-seq")
        s = reduce_proposal_event(s, conflicting)
        self.assertTrue(s.integrity_failed)
        self.assertTrue(s.vetoed)
        c = eligible()
        snapshot = replace(c.veto_ledger_read, integrity_ok=not s.integrity_failed,
                           vetoed=s.vetoed)
        self.assertFalse(check(replace(c, veto_ledger_read=snapshot)).eligible_for_final_recheck)

    def test_every_delivery_permutation_preserves_veto_and_gap_freedom(self):
        events = {
            1: self.event("provider_accepted", 1, at=NOW-4000),
            2: self.event("provider_accepted", 2, at=NOW-3600),
            3: self.event("veto", 3, at=NOW-1),
        }
        for ordering in permutations((1, 2, 3)):
            with self.subTest(delivery=ordering):
                state = self.state()
                seen = set()
                for sequence in ordering:
                    state = reduce_proposal_event(state, events[sequence])
                    seen.add(sequence)
                    prefix = 0
                    while prefix + 1 in seen:
                        prefix += 1
                    self.assertEqual(state.last_sequence, prefix)
                    self.assertEqual(state.processed_sequences, frozenset(seen))
                    if 3 in seen:
                        self.assertTrue(state.vetoed)
                self.assertTrue(state.vetoed)
                self.assertEqual(state.last_sequence, 3)
                c = eligible()
                ledger = replace(c.veto_ledger_read, committed_sequence=3,
                                 contiguous_sequence=3, vetoed=state.vetoed)
                self.assertFalse(
                    check(replace(c, veto_ledger_read=ledger)).eligible_for_final_recheck
                )

    def test_resend_cannot_shorten_accepted_veto_window(self):
        s=reduce_proposal_event(self.state(),self.event("provider_accepted",1))
        s=reduce_proposal_event(s,self.event("provider_accepted",2,at=NOW-1))
        self.assertEqual(s.email_accepted_at_s,NOW-3600)

    def test_veto_cannot_be_reversed_by_new_mail_event(self):
        s=reduce_proposal_event(self.state(),self.event("provider_accepted",1))
        s=reduce_proposal_event(s,self.event("veto",2,at=NOW-1))
        s=reduce_proposal_event(s,self.event("provider_accepted",3,at=NOW+20))
        self.assertTrue(s.vetoed)
        c=replace(eligible(),vetoed_proposal=s.vetoed,
                  email_accepted_at_s=s.email_accepted_at_s)
        self.assertFalse(check(c).eligible_for_final_recheck)

    def test_cross_identity_month_generation_or_bad_auth_fail_closed(self):
        s=self.state()
        for event in (
            replace(self.event("veto",1),generation=2),
            replace(self.event("veto",2),reason="budget"),
            replace(self.event("veto",3),month="2026-11"),
            replace(self.event("veto",4),proposal_id="other"),
            replace(self.event("veto",5),source_authenticated=False),
            replace(self.event("veto",6),event_id=""),
        ):
            self.assertEqual(reduce_proposal_event(s,event),s)

    def test_provider_acceptance_requires_recipient_and_receipt(self):
        s=self.state()
        bad=replace(self.event("provider_accepted",1),recipient_verified=False)
        self.assertEqual(reduce_proposal_event(s,bad),s)
        good=self.event("provider_accepted",2)
        self.assertEqual(reduce_proposal_event(s,good).email_accepted_at_s,NOW-3600)

    def test_resume_or_close_invalidates_old_proposal(self):
        for kind in ("resume","close"):
            s=reduce_proposal_event(self.state(),self.event(kind,1))
            self.assertTrue(s.closed)
            self.assertEqual(reduce_proposal_event(s,self.event("provider_accepted",2)),s)

    def test_budget_period_is_part_of_proposal_identity(self):
        s=ProposalLedger(proposal_id="budget-proposal",reason="budget",
                         month="2026-10",generation=1)
        e=ProposalEvent(event_id="budget-veto",proposal_id="budget-proposal",
                        reason="budget",month="2026-10",generation=1,sequence=1,
                        event_type="veto",timestamp_s=NOW,source_authenticated=True)
        self.assertTrue(reduce_proposal_event(s,e).vetoed)
        self.assertEqual(reduce_proposal_event(s,replace(e,month="2026-11")),s)


if __name__ == "__main__":
    unittest.main()
