// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart_pad.summarize;

import 'package:crypto/crypto.dart';

import '../services/dartservices.dart';

/// Instances of this class take string input of dart code as well as an
/// analysis result, and output a text description ofthe code's size, packages,
/// and other useful information.
class Summarizer {
  final String dart;
  final String html;
  final String css;
  final AnalysisResults analysis;

  _SummarizeToken storage;
  int _randomizer;

  static Map<String, List<int>> cuttoffs = {
    'size': [8, 30, 1000], //0-7 = small, 8 - 29 = decent, 29+ = gigantic
    'errorCount': [1, 5, 100]
  };

  static Map<String, String> codeKeyWords = {
    'await': 'await',
    'async': 'async',
    'rpc': 'RESTful serverside app'
  };

  static Map<String, String> additionKeyWords = {
    'pirate': 'pirates',
    'bird': 'birds',
    'llama': 'llamas',
    'dog': 'dogs'
  };

  static Map<String, List<String>> categories = {
    /// This [size] [codeQuantifier] contains [error] errors and warnings.
    'size-2': [
      'gigantic',
      'Jupiterian sized',
      'immense',
      'massive',
      'enormous',
      'huge',
      'epic',
      'humongous'
    ],
    'size-1': [
      'decently sized',
      'exceptional',
      'awesome',
      'amazing',
      'visionary',
      'legendary'
    ],
    'size-0': ['itty-bitty', 'miniature', 'tiny', 'pint-sized'],
    'compiledQuantifier': ['Dart program', 'pad'],
    'failedQuantifier': [
      'assemblage of characters',
      'series of strings',
      'grouping of letters'
    ],
    'errorCount-2': [
      'many',
      'a motherload of',
      'copious amounts of',
      'unholy quantities of'
    ],
    'errorCount-1': [
      'some',
      'a few',
      'sparse amounts of',
      'very few instances of'
    ],
    'errorCount-0': ['zero', 'no', 'a nonexistent amount of', '0.0000', '0'],
    'use': ['demonstrates', 'illustrates', 'depicts'],
    'code-0': ['it'],
    'code-1': ['It'],
  };

  Summarizer({this.dart, this.html, this.css, this.analysis}) {
    if (dart == null) throw new ArgumentError('Input cannot be null.');
    MD5 md5 = new MD5();
    md5.add(dart.codeUnits);
    _randomizer = _sumList(md5.close());
    storage = new _SummarizeToken(dart, analysis: analysis);
  }

  bool get hasAnalysisResults => analysis != null;

  int _sumList(List<int> list) => list.reduce((a, b) => a + b);

  String _categorySelector(String category, int itemCount) {
    if (category == 'size' || category == 'errorCount') {
      List<int> maxField = cuttoffs[category];
      for (int counter = 0; counter < maxField.length; counter++) {
        if (itemCount < maxField[counter]) return '${category}-${counter}';
        counter++;
      }
      return '${category}-${maxField.length - 1}';
    } else {
      return null;
    }
  }

  String _wordSelector(String category) {
    if (categories.containsKey(category)) {
      List<String> returnSet = categories[category];
      return returnSet.elementAt(_randomizer % returnSet.length);
    } else {
      return null;
    }
  }

  String _sentenceFiller(String word, [int size]) {
    if (size != null) {
      return _wordSelector(_categorySelector(word, size));
    } else {
      return _wordSelector(word);
    }
  }

  String _additionList(List<String> list) {
    if (list.length == 0) return '';
    String englishList = ' Also, mentions ';
    for (int i = 0; i < list.length; i++) {
      englishList += list[i];
      if (i < list.length - 2) englishList += ', ';
      if (i == list.length - 2) {
        if (i != 0) englishList += ',';
        englishList += ' and ';
      }
    }
    englishList += '. ';
    return englishList;
    // TODO: Tokenize features instead of returning as string.
  }

  List<String> additionSearch() => _additionSearch();

  bool _usedInDartSource(String feature) => dart.contains(feature);

  List<String> _additionSearch() {
    List<String> features = new List<String>();
    for (String feature in additionKeyWords.keys) {
      if (_usedInDartSource(feature)) features.add(additionKeyWords[feature]);
    }
    return features;
  }

  List<String> _codeSearch() {
    List<String> features = new List<String>();
    for (String feature in codeKeyWords.keys) {
      if (_usedInDartSource(feature)) features.add(codeKeyWords[feature]);
    }
    return features;
  }

  String _featureList(List<String> list) {
    if (list.length == 0) return '. ';
    String englishList = ', and ${_sentenceFiller('use')} use of ';
    for (int i = 0; i < list.length; i++) {
      englishList += list[i];
      if (i < list.length - 2) englishList += ', ';
      if (i == list.length - 2) {
        if (i != 0) englishList += ',';
        englishList += ' and ';
      }
    }
    englishList += ' features. ';
    return englishList;
  }

  String _packageList(List<String> list, {String source}) {
    if (list.length == 0) {
      return source == null ? '' : '. ';
    }

    String englishList = '';
    if (source == 'packages') {
      englishList += ', and ${_sentenceFiller('code-0')} imports ';
    } else {
      englishList += '${_sentenceFiller('code-1')} imports ';
    }

    for (int i = 0; i < list.length; i++) {
      englishList += "'${list[i]}'";
      if (i < list.length - 2) englishList += ', ';
      if (i == list.length - 2) {
        if (i != 0) englishList += ',';
        englishList += ' and ';
      }
    }

    if (source == 'packages') {
      englishList += ' from external packages. ';
    } else {
      englishList += ' from the dart package as well. ';
    }

    return englishList;
  }

  String _htmlCSS() {
    String htmlCSS = 'This code has ';
    if (!_hasHtml || html.length < 1) {
      htmlCSS += 'no ';
    } else {
      htmlCSS += 'some ';
    }
    htmlCSS += 'associated html and ';
    if (!_hasCSS || css.length < 1) {
      htmlCSS += 'no ';
    } else {
      htmlCSS += 'some ';
    }
    htmlCSS += 'associated css';
    return htmlCSS;
  }

  bool get _hasHtml => html != null && html.isNotEmpty;
  bool get _hasCSS => css != null && css.isNotEmpty;

  String returnAsSimpleSummary() {
    if (hasAnalysisResults) {
      String summary = '';
      summary += 'This ${_sentenceFiller('size', storage.linesCode)} ';
      if (storage.errorPresent) {
        summary += '${_sentenceFiller('failedQuantifier')} contains ';
      } else {
        summary += '${_sentenceFiller('compiledQuantifier')} contains ';
      }
      summary += '${_sentenceFiller('errorCount', storage.errorCount)} ';
      summary += 'errors and warnings';
      summary += '${_featureList(_codeSearch())}';
      summary += '${_htmlCSS()}';
      summary += '${_packageList(storage.packageImports, source: 'packages')}';
      summary += '${_packageList(storage.resolvedImports)}';
      summary += '${_additionList(_additionSearch())}';
      return summary;
    } else {
      String summary = "Summary: ";
      summary += 'This is a ${_sentenceFiller('size', storage.linesCode)} ';
      summary += '${_sentenceFiller('compiledQuantifier')}';
      summary += '${_featureList(_codeSearch())}';
      summary += '${_htmlCSS()}';
      summary += '${_additionList(_additionSearch())}';
      return summary;
    }
  }

  String returnAsMarkDown() {
    // For now, we're just returning plain text. This might change at some point
    // to include some markdown styling as well.
    return returnAsSimpleSummary();
  }
}

class _SummarizeToken {
  int linesCode;
  int packageCount;
  int resolvedCount;
  int errorCount;
  int warningCount;

  bool errorPresent;
  bool warningPresent;

  List<String> packageImports;
  List<String> resolvedImports;

  List<AnalysisIssue> errors;

  _SummarizeToken(String input, {AnalysisResults analysis}) {
    linesCode = _linesOfCode(input);
    if (analysis != null) {
      errorPresent = analysis.issues.any((issue) => issue.kind == 'error');
      warningPresent = analysis.issues.any((issue) => issue.kind == 'warning');
      packageCount = analysis.packageImports.length;
      resolvedCount = analysis.resolvedImports.length;
      packageImports = analysis.packageImports;
      resolvedImports = analysis.resolvedImports;
      errors = analysis.issues;
      errorCount = errors.length;
    }
  }

  int _linesOfCode(String input) => input.split('\n').length;
}
