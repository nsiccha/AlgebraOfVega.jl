(function() {
  if (typeof document === 'undefined') return;
  var _explorerDatasets, _explorerColumns;

  function init() {
    var scripts = document.querySelectorAll('script[src*="explorer.js"]');
    var base = '';
    if (scripts.length > 0) {
      var src = scripts[scripts.length - 1].src;
      base = src.substring(0, src.lastIndexOf('/'));
    }
    Promise.all([
      fetch(base + '/explorer-data.json'),
      fetch(base + '/explorer-columns.json'),
    ]).then(function(responses) {
      return Promise.all(responses.map(function(r) { return r.json(); }));
    }).then(function(data) {
      _explorerDatasets = data[0];
      _explorerColumns = data[1];
      explorerUpdate();
    });
  }

  window._explorerUpdateDropdowns = function() {
    var ds = document.getElementById('ex-dataset').value;
    var cols = _explorerColumns[ds];
    var allCols = cols.all;
    var catCols = cols.categorical;
    ['ex-x', 'ex-y'].forEach(function(id) {
      var sel = document.getElementById(id);
      var prev = sel.value;
      sel.innerHTML = '';
      allCols.forEach(function(c) {
        var opt = document.createElement('option');
        opt.value = c; opt.textContent = c;
        sel.appendChild(opt);
      });
      if (allCols.indexOf(prev) >= 0) sel.value = prev;
      else if (id === 'ex-y' && allCols.length > 1) sel.value = allCols[1];
    });
    ['ex-color', 'ex-group', 'ex-col', 'ex-row'].forEach(function(id) {
      var sel = document.getElementById(id);
      var prev = sel.value;
      sel.innerHTML = '<option value="">(none)</option>';
      catCols.forEach(function(c) {
        var opt = document.createElement('option');
        opt.value = c; opt.textContent = c;
        sel.appendChild(opt);
      });
      if (catCols.indexOf(prev) >= 0) sel.value = prev;
      else sel.value = '';
    });
  };

  window.explorerUpdate = function() {
    if (!_explorerDatasets) return;
    var ds = document.getElementById('ex-dataset').value;
    var x = document.getElementById('ex-x').value;
    var y = document.getElementById('ex-y').value;
    var color = document.getElementById('ex-color').value;
    var group = document.getElementById('ex-group').value;
    var facetCol = document.getElementById('ex-col').value;
    var facetRow = document.getElementById('ex-row').value;
    var mark = document.getElementById('ex-mark').value;
    var data = _explorerDatasets[ds];
    function fieldType(field) {
      for (var i = 0; i < data.length; i++) {
        var v = data[i][field];
        if (v !== null && v !== undefined) return typeof v === 'number' ? 'quantitative' : 'nominal';
      }
      return 'nominal';
    }
    var encoding = {
      x: {field: x, type: fieldType(x)},
      y: {field: y, type: fieldType(y)},
      tooltip: [{field: x, type: fieldType(x)}, {field: y, type: fieldType(y)}],
    };
    if (color) {
      encoding.color = {field: color, type: 'nominal'};
      encoding.tooltip.push({field: color, type: 'nominal'});
    }
    if (group) {
      encoding.detail = {field: group, type: 'nominal'};
    }
    var spec;
    if (facetCol || facetRow) {
      var facet = {};
      if (facetCol) facet.column = {field: facetCol, type: 'nominal'};
      if (facetRow) facet.row = {field: facetRow, type: 'nominal'};
      spec = {data: {values: data}, facet: facet, spec: {mark: mark, encoding: encoding, width: 250, height: 200}};
    } else {
      spec = {data: {values: data}, mark: mark, encoding: encoding, width: 600, height: 350};
    }
    function doEmbed() {
      vegaEmbed('#explorer-plot', spec, {actions: false}).catch(console.error);
    }
    if (typeof vegaEmbed !== 'undefined') { doEmbed(); }
    else {
      var check = setInterval(function() {
        if (typeof vegaEmbed !== 'undefined') { clearInterval(check); doEmbed(); }
      }, 100);
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
