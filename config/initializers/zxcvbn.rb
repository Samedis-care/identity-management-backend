# Zxcvbn.test lazily builds a process-wide shared Tester on first call: Zxcvbn::Data#initialize
# reads ~800 KB of frequency lists plus adjacency_graphs.json and builds a Trie per dictionary,
# all inside a mutex (see zxcvbn-ruby's lib/zxcvbn.rb). Measured cost: ~340ms cold, ~0.2ms warm.
#
# Without this warmup, the first POST /register (or any password create/change) after each
# boot pays that whole cost inline, and any concurrent password request blocks on the same
# mutex until it finishes — issue #2425 review finding. Warming it here moves the cost to
# boot/deploy instead of a user request. The tries stay resident per Puma worker afterwards.
Zxcvbn.test('warmup')
