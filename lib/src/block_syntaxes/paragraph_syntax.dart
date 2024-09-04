// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../ast.dart';
import '../block_parser.dart';
import '../patterns.dart';
import 'block_syntax.dart';
import 'empty_block_syntax.dart';
import 'setext_header_syntax.dart';

/// Parses paragraphs of regular text.
class ParagraphSyntax extends BlockSyntax {
  @override
  RegExp get pattern => dummyPattern;

  @override
  bool canEndBlock(BlockParser parser) => false;

  const ParagraphSyntax();

  @override
  bool canParse(BlockParser parser) => true;

  @override
  Node? parse(BlockParser parser) {
    final childLines = <String>[parser.current.content];
    final preserveSpace = parser.document.preserveSpace;
    if (preserveSpace) {
      //Look backward to merge empty lines in front of it
      var n = 0,
        diffSyntaxFound = false;
      while (parser.pos > 0) {
        --n;
        parser.retreat();
        if (!const EmptyBlockSyntax().canParse(parser)) {
          diffSyntaxFound = true;
          break;
        }

        childLines.insert(0, parser.current.content);
      }
      if (n < 0) {
        //If not retreat to a diff syntax, remove the separator, i.e.,
        //ingore one empty line
        if (diffSyntaxFound && childLines.length > 1) {
          childLines.removeAt(0); //remove the separator
        }

        parser.retreatBy(n); //restore pos
      }
    }

    parser.advance();
    var interruptedBySetextHeading = false;
    // Eat until we hit something that ends a paragraph.
    l_done:
    while (!parser.isDone) {
      if (preserveSpace) {
        //Look ahead and merge empty paragraphs following it
        while (const EmptyBlockSyntax().canParse(parser)) {
          childLines.add(parser.current.content);
          parser.advance();
          if (parser.isDone) break l_done;
        }
      }

      final syntax = interruptedBy(parser);
      if (syntax != null) {
        interruptedBySetextHeading = syntax is SetextHeaderSyntax;
        break;
      }
      childLines.add(parser.current.content);
      parser.advance();
    }

    // It is not a paragraph, but a setext heading.
    if (interruptedBySetextHeading) {
      return null;
    }

    final content = childLines.join('\n'),
      contents = UnparsedContent(preserveSpace ? content: content.trimRight());
    return Element('p', [contents]);
  }
}
