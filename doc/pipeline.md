<!-- Written by test/finder/pipeline_test.dart; rewrite it with
     `UPDATE_GOLDENS=1 dart test test/finder/pipeline_test.dart`. -->

# How a scan runs

Each box is a step of a scan, and a box that holds other boxes runs them in
order. The diagram is drawn from scans of `example/`, so it shows the steps
that `lib/src/finder.dart` and `lib/src/settle/settler.dart` mark with
`stage(…)`. A note under a step names the options that it depends on.

```mermaid
flowchart TD
  s0["Discover Dart files"]
  s1["Start the analysis server"]
  s2["Wait for the initial analysis"]
  s3["Open files"]
  s4["Collect declarations"]
  subgraph s5 ["Fetch references"]
    subgraph s5_0 ["Check references"]
      s5_0_0["Find references"]
      s5_0_1["Fetch semantic tokens at the references"]
      s5_0_0 --> s5_0_1
    end
    s5_1["Find the types that exported signatures hand out<br/><i>only with <code>--exported-packages=.</code></i>"]
    s5_2["Look up uses of members of unexported types<br/><i>only with <code>--exported-packages=.</code></i>"]
    subgraph s5_3 ["Check references of the members that no lookup found used<br/><i>only with <code>--exported-packages=.</code></i>"]
      s5_3_0["Find references"]
      s5_3_1["Fetch semantic tokens at the references"]
      s5_3_0 --> s5_3_1
    end
    s5_0 --> s5_1 --> s5_2 --> s5_3
  end
  s6["Share references between conditional-import variants"]
  s7["Fetch selection ranges"]
  subgraph s8 ["Settle findings"]
    s8_0["Find the declarations that no live code reaches<br/><i>skipped with <code>--no-transitive</code></i>"]
    subgraph s8_1 ["Settle a round<br/><i>repeats</i>"]
      s8_1_0["Recover the references that the search missed"]
      s8_1_1["Classify references"]
      s8_1_2["Check which findings can be removed safely"]
      s8_1_3["Find the overrides of dead members"]
      s8_1_4["Work out how to cut out dead fields and variables"]
      s8_1_5["Find the types that only <code>with</code> and <code>implements</code> clauses name"]
      s8_1_6["Sweep the findings that no live reference reaches<br/><i>skipped with <code>--no-transitive</code></i>"]
      s8_1_0 --> s8_1_1 --> s8_1_2 --> s8_1_3 --> s8_1_4 --> s8_1_5 --> s8_1_6
    end
    s8_0 --> s8_1
  end
  s0 --> s1 --> s2 --> s3 --> s4 --> s5 --> s6 --> s7 --> s8
```
