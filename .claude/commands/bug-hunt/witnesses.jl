#!/usr/bin/env julia
# The witness runner — the mechanical half of /bug-hunt, and the reason the instrument can verify its
# own fixes without asking an agent whether the fix worked.
#
# Every confirmed defect leaves behind a WITNESS: a self-contained `@testset` asserting the CORRECT
# behaviour, which therefore FAILS on the defective tree. That single artifact does three jobs no
# prose finding can do:
#
#   1. AT HUNT TIME it proves the defect exists. A candidate whose witness passes was never a bug,
#      whatever the argument for it was.
#   2. AT FIX TIME it defines "done" without a judgement call. The fix is complete exactly when the
#      witness flips, and not when an agent says it looks right.
#   3. AFTER THE FIX it is a regression test, unchanged, ready to be promoted into `test/`.
#
# So the fix verifier is `expect=pass` and the hunt verifier is `expect=fail`, and both are a program
# exiting non-zero rather than an opinion.
#
# The expectation is REQUIRED and there is no default, because the two directions are the whole point
# and a runner that guesses would let a mis-specified round report success. Two failure modes are
# reported LOUDLY rather than passed over, both of which are the instrument lying to itself:
#
#   * expect=fail and the witness PASSES  — a phantom bug. The finding must be withdrawn.
#   * expect=pass and the witness FAILS   — the fix did not land, or landed on the wrong site.
#
# A witness that ERRORS (does not load, throws outside a @test) is neither pass nor fail and is
# reported as BROKEN in both directions: it is evidence of nothing, and counting it as a failure is
# how a broken witness masquerades as a proven bug.
#
#   julia --project .claude/commands/bug-hunt/witnesses.jl fail    # at hunt time: all must fail
#   julia --project .claude/commands/bug-hunt/witnesses.jl pass    # after fixes: all must pass
#   julia --project .claude/commands/bug-hunt/witnesses.jl pass 03-aliasing-02   # one witness

const DIR = joinpath(@__DIR__, "..", "..", "bug-hunt", "witnesses")

function main(args)
  isempty(args) && (println("usage: witnesses.jl <fail|pass> [name…]"); exit(2))
  expect = args[1]
  expect in ("fail", "pass") || (println("expectation must be `fail` or `pass`, got `$expect`"); exit(2))

  isdir(DIR) || (println("no witness directory at $DIR"); exit(2))
  files = sort(filter(f -> endswith(f, ".jl"), readdir(DIR)))
  if length(args) > 1
    wanted = args[2:end]
    files = filter(f -> any(w -> occursin(w, f), wanted), files)
    isempty(files) && (println("no witness matched $(wanted)"); exit(2))
  end
  # An empty run must NEVER read as success: a wrong directory, an archived pile, or a name that
  # matched nothing would otherwise print a clean tally and exit 0 — the silent-success path this
  # project has now been bitten by in three separate instruments.
  isempty(files) && (println("REFUSING: no witnesses found in $DIR — nothing was verified"); exit(2))

  passed, failed, broken = String[], String[], String[]
  for f in files
    path = joinpath(DIR, f)
    out = IOBuffer()
    # A fresh process per witness: a witness that corrupts global state, or one that segfaults on a
    # device array, must not decide the verdict of the next.
    p = run(pipeline(`$(Base.julia_cmd()) --project=$(dirname(Base.active_project())) --startup-file=no $path`,
                     stdout = out, stderr = out), wait = false)
    wait(p)
    text = String(take!(out))
    code = p.exitcode
    # Test.jl exits 1 on a failed @test and prints a summary; a load error or a throw outside a
    # @test also exits 1, so the exit code alone cannot separate "the assertion failed" (evidence)
    # from "the file is broken" (no evidence at all).
    testfail = occursin("Test Failed", text) || occursin("Some tests did not pass", text)
    if code == 0
      push!(passed, f)
    elseif testfail
      push!(failed, f)
    else
      push!(broken, f)
      println("── BROKEN: $f ", "─"^max(0, 60 - length(f)))
      println(strip(text)[1:min(end, 1200)])
    end
  end

  for f in passed;  println("PASS   $f") end
  for f in failed;  println("FAIL   $f") end
  for f in broken;  println("BROKEN $f") end
  println("\n$(length(files)) witness(es): $(length(passed)) pass, $(length(failed)) fail, $(length(broken)) broken")
  println("expectation: every witness must $(uppercase(expect))")

  wrong = expect == "fail" ? passed : failed
  label = expect == "fail" ?
    "PHANTOM — these witnesses PASS on the current tree, so the defect they claim does not exist. Withdraw the finding." :
    "UNFIXED — these witnesses still FAIL, so the fix did not land (or landed on the wrong site)."
  if !isempty(wrong)
    println("\n!! $label")
    for f in wrong; println("   !! $f") end
  end
  if !isempty(broken)
    println("\n!! BROKEN — these witnesses are evidence of NOTHING in either direction. Repair or discard them;")
    println("!! do not count a broken witness as a proven bug.")
    for f in broken; println("   !! $f") end
  end
  exit(isempty(wrong) && isempty(broken) ? 0 : 1)
end

main(ARGS)
