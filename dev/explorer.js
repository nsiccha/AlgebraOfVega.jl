(function() {
  if (typeof document === 'undefined') return;
  var _explorerDatasets, _explorerColumns;
  var _explorerFilterSelected = {};

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

  window._explorerUpdateFilterPills = function(activeCols, data) {
    var container = document.getElementById('ex-filter-pills');
    if (!container) return;
    container.innerHTML = '';
    if (!activeCols || activeCols.length === 0 || !data) return;
    var stored = _explorerFilterSelected;
    activeCols.forEach(function(col) {
      var unique = {};
      for (var i = 0; i < data.length; i++) {
        var v = data[i][col];
        if (v !== null && v !== undefined) unique[String(v)] = true;
      }
      var values = Object.keys(unique).sort();
      if (!stored[col]) {
        stored[col] = new Set(values);
      }
      var row = document.createElement('div');
      row.style.cssText = 'display:flex; flex-wrap:wrap; align-items:center; gap:0.3rem; margin-bottom:0.25rem;';
      var label = document.createElement('strong');
      label.textContent = col + ': ';
      label.style.cssText = 'font-size:0.85rem; min-width:5rem;';
      row.appendChild(label);
      values.forEach(function(v) {
        var pill = document.createElement('button');
        pill.type = 'button';
        pill.textContent = v;
        var sel = stored[col].has(v);
        pill.style.cssText = 'border:1px solid var(--pico-primary);border-radius:1rem;padding:0.15rem 0.6rem;cursor:pointer;font-size:0.85rem;' +
          (sel ? 'background:var(--pico-primary);color:var(--pico-primary-inverse);' : 'background:transparent;color:var(--pico-primary);');
        pill.onclick = function(e) {
          if (e.ctrlKey || e.metaKey) {
            stored[col] = new Set([v]);
          } else {
            if (stored[col].has(v)) stored[col].delete(v);
            else stored[col].add(v);
          }
          explorerUpdate();
        };
        row.appendChild(pill);
      });
      container.appendChild(row);
    });
  };

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
      if (!sel) return;
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
    var rawData = _explorerDatasets[ds];
    var activeCatCols = [];
    [color, group, facetCol, facetRow].forEach(function(c) {
      if (c && activeCatCols.indexOf(c) < 0) activeCatCols.push(c);
    });
    _explorerUpdateFilterPills(activeCatCols, rawData);
    var data = rawData;
    var stored = _explorerFilterSelected;
    activeCatCols.forEach(function(col) {
      if (stored[col] && stored[col].size > 0) {
        data = data.filter(function(row) { return stored[col].has(String(row[col])); });
      }
    });
    function fieldType(field) {
      for (var i = 0; i < data.length; i++) {
        var v = data[i][field];
        if (v !== null && v !== undefined) return typeof v === 'number' ? 'quantitative' : 'nominal';
      }
      return 'nominal';
    }
    var xType = fieldType(x), yType = fieldType(y);
    var zeroX = xType === 'quantitative' && (mark === 'bar') ? {} : {zero: false};
    var zeroY = yType === 'quantitative' && (mark === 'bar') ? {} : {zero: false};
    var encoding = {
      x: {field: x, type: xType, scale: zeroX},
      y: {field: y, type: yType, scale: zeroY},
      tooltip: [{field: x, type: xType}, {field: y, type: yType}],
    };
    if (color) {
      encoding.color = {field: color, type: 'nominal'};
      encoding.tooltip.push({field: color, type: 'nominal'});
    }
    if (group) {
      encoding.detail = {field: group, type: 'nominal'};
    }
    var indepX = document.getElementById('ex-indep-x') && document.getElementById('ex-indep-x').checked;
    var indepY = document.getElementById('ex-indep-y') && document.getElementById('ex-indep-y').checked;
    var spec;
    if (facetCol || facetRow) {
      var facet = {};
      if (facetCol) facet.column = {field: facetCol, type: 'nominal'};
      if (facetRow) facet.row = {field: facetRow, type: 'nominal'};
      var plotEl = document.querySelector('#explorer-plot');
      var availWidth = plotEl ? plotEl.clientWidth : 800;
      var cellWidth = 250;
      if (facetCol) {
        var uniqueCols = {};
        for (var i = 0; i < data.length; i++) { uniqueCols[data[i][facetCol]] = true; }
        var nCols = Object.keys(uniqueCols).length;
        if (nCols > 0) cellWidth = Math.max(100, Math.floor((availWidth - 60) / nCols));
      } else {
        cellWidth = Math.max(250, availWidth - 60);
      }
      spec = {data: {values: data}, facet: facet, spec: {mark: mark, encoding: encoding, width: cellWidth, height: 200}};
      if (indepX || indepY) {
        var resolve = {scale: {}, axis: {}};
        if (indepX) { resolve.scale.x = 'independent'; resolve.axis.x = 'independent'; }
        if (indepY) { resolve.scale.y = 'independent'; resolve.axis.y = 'independent'; }
        spec.resolve = resolve;
      }
    } else {
      spec = {data: {values: data}, mark: mark, encoding: encoding, width: 'container', height: 350};
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
