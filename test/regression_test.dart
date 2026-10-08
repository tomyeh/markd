// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:markd/markdown.dart';
import 'package:test/test.dart';

void main() {
  test('HTML comment with dashes #2119', () {
    // See https://dartbug.com/tools/2119.
    // For this issue, the leading letter was needed,
    // an HTML comment starting a line is handled by a different path.
    // The empty line before the `-->` is needed.
    // The number of lines increase time exponentially.
    // The length of lines affect the base of the exponentiation.
    // Locally, three "Lorem-ipsum" lines ran in ~6 seconds, two in < 200 ms.
    // Adding a fourth line should ensure it cannot possibly finish in ten
    // seconds if the bug isn't fixed.
    const input = '''
a <!-- 
    - Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
      tempor incididunt ut labore et dolore magna aliqua.
      Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi
      ut aliquip ex ea commodo consequat.
    - Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
      tempor incididunt ut labore et dolore magna aliqua.
      Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi
      ut aliquip ex ea commodo consequat.
    - Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
      tempor incididunt ut labore et dolore magna aliqua.
      Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi
      ut aliquip ex ea commodo consequat.
    - Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
      tempor incididunt ut labore et dolore magna aliqua.
      Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi
      ut aliquip ex ea commodo consequat.
-->
''';

    final time = Stopwatch()..start();
    final html = markdownToHtml(input); // Should not hang.
    expect(html, isNotNull); // To use the output.
    final elapsed = time.elapsedMilliseconds;
    expect(elapsed, lessThan(10000));
  });

  test('HTML comment with lt/gt', () {
    // Incorrect parsing found as part of fixing #2119.
    // Now matches `<!--$text-->` where text
    // does not start with `>` or `->`, does not end with `-`,
    // and does not contain `--`.
    const input = 'a <!--<->>-<!-->';
    final html = markdownToHtml(input);
    expect(html, '<p>$input</p>\n');
  });

  test('setext heading underline is not an empty list item, GFM #2108', () {
    // See https://github.com/dart-lang/tools/issues/2108.
    // With `ExtensionSet.gitHubFlavored`, `UnorderedListWithCheckboxSyntax`
    // used to be checked before `SetextHeaderSyntax`, so a lone `-` line
    // continuing a paragraph was parsed as an empty list item instead of a
    // setext H2 underline.
    final html = markdownToHtml(
      'I am paragraph\n-',
      extensionSet: ExtensionSet.gitHubFlavored,
    );
    expect(html, '<h2>I am paragraph</h2>\n');
  });

  test('long unbroken word does not take quadratic time', () {
    // The plain-text accelerator regex required a trailing whitespace, so a
    // long run of word characters that reached the end of a line without one
    // (a single long word) forced the regex to backtrack across the whole run
    // at every position, giving quadratic parse time. A ~200k character word
    // used to take tens of seconds; it should now be effectively instant.
    final input = '${'a' * 200000}\n';

    final time = Stopwatch()..start();
    final html = markdownToHtml(input); // Should not hang.
    expect(html, isNotNull); // To use the output.
    expect(time.elapsedMilliseconds, lessThan(10000));
  });

  test('table delimiter row that almost matches does not take exponential time',
      () {
    // Adjacent `[ \t]*` quantifiers in `tablePattern` let the engine try every
    // split of each whitespace run when the row failed to match, so a padded
    // 12-column delimiter row with a stray character at the end took 40
    // seconds. It should now be effectively instant, and remain a paragraph.
    final input = 'a | b\n${'|    ---    ' * 12}|.\n';

    final time = Stopwatch()..start();
    final html =
        markdownToHtml(input, extensionSet: ExtensionSet.gitHubFlavored);
    expect(html, '<p>a | b\n${'|    ---    ' * 12}|.</p>\n');
    expect(time.elapsedMilliseconds, lessThan(10000));
  });

  test('other table delimiter rows that almost match are linear too', () {
    for (final line in [
      '${'|\t\t---\t\t' * 12}|x',
      '${'|    ---    ' * 6}| --x-- ${'|    ---    ' * 6}|',
      '${'| :---: ' * 12}|.',
      '|${'-' * 2000}x|',
      '${'|    ---    ' * 30}|.',
    ]) {
      final time = Stopwatch()..start();
      final html = markdownToHtml('a | b\n$line\n',
          extensionSet: ExtensionSet.gitHubFlavored);
      expect(html, '<p>a | b\n$line</p>\n');
      expect(time.elapsedMilliseconds, lessThan(10000), reason: line);
    }
  });

  test('a line that more than one block syntax fails to parse', () {
    // `parseLines` remembered only the last syntax that didn't advance, so
    // `TableSyntax` and `LinkReferenceDefinitionSyntax` took turns failing at
    // the same line until it threw "BlockParser.parseLines is not advancing".
    final gfm = ExtensionSet.gitHubFlavored;
    expect(markdownToHtml('[a] | b\n|-|', extensionSet: gfm),
        '<p>[a] | b\n|-|</p>\n');
    expect(markdownToHtml('[|:\n-|', extensionSet: gfm),
        '<p>[|:\n-|</p>\n');
    expect(markdownToHtml('[a]: b | c\n|-|', extensionSet: gfm),
        '<p>[a]: b | c\n|-|</p>\n');
    expect(markdownToHtml('- [a] | b\n  |-|', extensionSet: gfm),
        '<ul>\n<li>[a] | b\n|-|</li>\n</ul>\n');
  });

  test('deeply nested blocks do not overflow the stack', () {
    // Each nested blockquote or list item parsed its lines recursively, so
    // 10,000 `>` overflowed the stack. Lines nested deeper than
    // `BlockParser.maxNestingLevel` (32) are parsed as a paragraph.
    expect(markdownToHtml('${'>' * 32}x'),
        '${'<blockquote>\n' * 32}<p>x</p>\n${'</blockquote>\n' * 32}');
    expect(markdownToHtml('${'>' * 33}x'),
        '${'<blockquote>\n' * 32}<p>&gt;x</p>\n${'</blockquote>\n' * 32}');
    expect(markdownToHtml('${'>' * 10000}x'),
        '${'<blockquote>\n' * 32}<p>${'&gt;' * 9968}x</p>\n'
        '${'</blockquote>\n' * 32}');
    expect(markdownToHtml('${'- ' * 5000}x'),
        '${'<ul>\n<li>\n' * 31}<ul>\n<li>${'- ' * 4968}x</li>\n</ul>\n'
        '${'</li>\n</ul>\n' * 31}');
  });

  test('list item that starts with an empty line', () {
    // The counter of leading blank lines wasn't reset once the item's content
    // began, so every line was parsed for a task list marker (overwriting or
    // clearing the first one's state), and a blank line between the item's
    // paragraphs ended the item.
    final gfm = ExtensionSet.gitHubFlavored;
    expect(markdownToHtml('-\n  [x] foo\n  [ ] bar', extensionSet: gfm), '''
<ul class="contains-task-list">
<li class="task-list-item"><input type="checkbox" disabled="disabled" checked="true"></input>foo
[ ] bar</li>
</ul>
''');
    expect(markdownToHtml('-\n  [ ] foo\n  bar', extensionSet: gfm), '''
<ul class="contains-task-list">
<li class="task-list-item"><input type="checkbox" disabled="disabled"></input>foo
bar</li>
</ul>
''');
    expect(markdownToHtml('-\n  foo\n\n  bar'), '''
<ul>
<li>
<p>foo</p>
<p>bar</p>
</li>
</ul>
''');
  });

  test('data-line of a task list item after an empty first line', () {
    // The item's children were parsed with the offset of the dropped empty
    // line, so their `data-line` was off by one.
    String render(String markdown) => HtmlRenderer().render(
        Document(extensionSet: ExtensionSet.gitHubFlavored, checkable: true)
            .parseLines(markdown.split('\n')));
    expect(render('-\n  - [ ] a\n  - [ ] b'), '''
<ul>
<li>
<ul class="contains-task-list">
<li class="task-list-item"><input type="checkbox" data-line="1"></input>a</li>
<li class="task-list-item"><input type="checkbox" data-line="2"></input>b</li>
</ul>
</li>
</ul>''');
    expect(render('-\n  [x] foo'), '''
<ul class="contains-task-list">
<li class="task-list-item"><input type="checkbox" data-line="1" checked="true"></input>foo</li>
</ul>''');
    expect(render('- [ ] \n  foo'), '''
<ul class="contains-task-list">
<li class="task-list-item"><input type="checkbox" data-line="0"></input>foo</li>
</ul>''');
  });
}
