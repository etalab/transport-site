<shortlist>
<section each={ item in shortlist }>
  <img src={ item.logo }/>
  <h1>{ item.title }</h1>
  <markdown content={ item.description }/>
  <footer>
    <span class="download"><i class="fa fa-download" aria-hidden="true"></i>
      <a href="#">{ parent.opts.download }</a>
    </span>
    <div class="details">
      <div><span>{ parent.opts.licence } :</span> <span class="badge-notice">{ item.license } </span></div>
      <div><span>Format :</span> <span class="badge-notice">GTFS</span></div>
    </div>
  </footer>
</section>


<script type="es6">
this.shortlist = []

this.fetch_shortlist = () => {
  var licences = {
    'odc-odbl': 'ODbL',
    'fr-lo': opts.frlo
  }
  fetch('/data/datasets.json',)
    .then(response => { return response.json() })
    .then(data => {
      data = data.filter(l => l['anomalies'].length == 0)
      data.forEach(l => l['license'] = licences[l['license']])
      this.update( this.shortlist = data )
     })
}
this.on('mount', this.fetch_shortlist)
</script>
</shortlist>
