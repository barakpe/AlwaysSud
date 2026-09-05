# Draft email to Udi

Three separate asks, deliberately ordered so the cheapest one to answer is first.
Everything is phrased so he can reply with three short lines.

---

**Subject:** Hackathon scoring — which boards, and when do we get the variant?

Hi Udi,

I'm deep in optimising the Sudoku accelerator and I've hit three things I can't
settle without you. Sorry for the list — each one is short.

**1. Which puzzles are actually scored, and how are they combined?**

You said the competition is best `cycles / F_max`. That's clear for a single
puzzle, but the cycle count varies enormously between boards — on our own four,
the same design ranges from tens of cycles to over a hundred million. So the
ranking depends completely on which boards go into the score and how they're
combined. Could you confirm:

- Is it **one specific puzzle**, or a set?
- If it's a set, is the score the **sum** of cycles, the **mean**, the **worst
  case**, or the rate computed per-board and then averaged?
- Are the scored puzzles the four in the course repo (`easy1`, `20blanks`,
  `51blanks`, `hard1`), or new ones we haven't seen?

The reason this matters more than it sounds: I have two designs where **on
`easy1`, `20blanks` and `51blanks` the cycle counts are literally identical**,
and they differ by more than 10x on harder inputs. If the score is dominated by
the easy boards, the two are indistinguishable and the ranking is essentially
noise; if it's dominated by a hard board, they're an order of magnitude apart.
I'd rather optimise for the real metric than guess.

Also, just to confirm the denominator: is `F_max` the **standalone accelerator**
figure from `qsyn_xlr`, or the **full-system** figure from `comp_fpga`? I've been
working to the standalone number and treating the 50 MHz system clock as not
graded — please tell me if that's wrong, because it changes what I optimise.

**2. When will the hackathon variant be announced?**

I'd like to prepare rather than react. I've already built the geometry as a
configuration table instead of hard-coded row/column/box logic, so variants that
are of the form *"these nine cells must all be different"* — X-Sudoku, Windoku,
jigsaw — are a one-line change for me and I've tested them.

What I **cannot** absorb late are variants that aren't of that form: anti-knight,
thermometers, killer cages with sums, or inequality constraints. Those need a
different solver *and* a different correctness checker, and they're not something
I can retrofit on the day.

So even a partial answer helps enormously — even just *"it will / won't be a
pure all-different constraint"* would let me prepare properly. If there's a date
when the variant is released, could you share it?

**3. The cloud environment, and reducing the risk on the day**

I lost a lot of this weekend to the RC cloud. The connection kept dropping, and
several long synthesis runs were lost partway through. That's survivable while
I'm exploring, but it worries me for the hackathon itself: a full FPGA build for
my current design takes **hours**, not the ~5 minutes the reference design takes,
and a dropped connection mid-build costs the whole run.

Two things that would take most of the pressure off the due day:

- Could we **submit or freeze the design earlier** than the deadline, or bank an
  intermediate submission, so that a bad connection on the day isn't fatal?
- Is there any way to get **more stable / longer-lived sessions** on the cloud
  for the hackathon window — or guidance on the right way to run long builds so
  they survive a disconnect?

If neither is possible, that's fine — but knowing now means I'll plan to have a
working bitstream built and verified well before the deadline rather than
counting on building on the day.

Thanks a lot,
Barak

---

## Why each question is phrased that way

**Q1** is the one that actually changes engineering decisions. The concrete detail
about two designs being *identical on three boards* is worth keeping — it turns an
abstract question into something he can see the point of immediately. The F_max
follow-up is deliberately separate: it is a one-word answer and it decides whether
the whole optimisation target is right.

**Q2** gives him an easy partial answer. "Is it all-different or not" is much
easier to say than "here is the variant", and it is genuinely the information that
changes what is worth building.

**Q3** is framed as risk reduction rather than a complaint, and offers two concrete
options so he can pick one instead of having to invent a solution.
