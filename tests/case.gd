## Base class for the test files: `check`, `eq` and `near` record failures, and
## run.gd reports them. A test method may await frames.
extends RefCounted

var failures: Array = []


func check(cond: bool, msg: String = "check failed") -> void:
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String = "") -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


func near(actual: float, expected: float, tol: float = 0.001, msg: String = "") -> void:
	if absf(actual - expected) > tol:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])
