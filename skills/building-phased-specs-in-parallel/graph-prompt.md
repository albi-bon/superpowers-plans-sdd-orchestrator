# Graph Dispatch Template

Dispatched at most once per run, at preflight, and only when the design document
has no `Depends on` line in any phase section. The graph agent reads how the
document states its phase dependencies — a dependency section, a table, a
diagram, or prose — and writes them in the one shape the scheduler reads. It
never sees the repository's code. Substitute every uppercase placeholder value
before dispatching.

```
Subagent (general-purpose; portable envelope — see platform-guide.md):
  description: "Read the phase graph of DESIGN_DOC_BASENAME"
  model: a mid-tier model — this is careful reading of one document, not
         judgement about code. Resolve the actual model through
         platform-guide.md; record inheritance if selection is unavailable.
  prompt: |
    Read applicable repository instructions. All artifact paths below are absolute.

    Read a phased design document and write down which phases depend on which.
    Phases with no dependency between them will be built at the same time, so
    an edge you miss lets two phases race; an edge you invent only costs time.

    Design document: DESIGN_DOC
    Phases:          PHASE_LIST   (one per line: number<TAB>title)
    Graph file:      GRAPH_PATH

    Do not spawn subagents; complete this bounded role yourself.

    ## Your job

    1. Read the whole design document. Look for every place it states an
       order or a dependency between phases: a dependency section or table,
       a diagram, a phase's own text ("builds on phase 2", "after phase 3
       lands", "uses the API phase 4 adds"), a decision log entry.
    2. For each phase in PHASES, list the phases it depends on, by the number
       in their heading. A dependency must name a phase in PHASES.
    3. Where the document says nothing about a phase's dependencies, that
       phase depends on the phase with the next lower number in PHASES. The
       first phase then depends on nothing. Never read independence into
       silence.
    4. Where what the document states would form a cycle, give every phase in
       the cycle that same next-lower default instead.
    5. Write GRAPH_PATH: one line per phase in PHASES, in ascending numeric
       order, three tab-separated fields:

       ~~~
       <number><TAB><dependencies, comma-separated, or -><TAB>agent
       ~~~

       For example `4	2,3	agent`, or `2	-	agent` for a phase with no
       dependencies. Nothing else in the file.

    ## Constraints

    - You write GRAPH_PATH and nothing else. You edit no source file, run no
      Git command that changes anything, and make no commit.

    ## Return contract

    At most three lines:
    - GRAPH_PATH
    - phases: <count>
    - edges: <count of dependencies written>

    Do not paste the graph, document text, or your reasoning into your reply.
    The graph file is where the result goes.
```
