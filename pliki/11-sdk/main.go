// Dashboard v2 "SDK — <login>" zbudowany Foundation SDK (Go) dla ćwiczenia 09 modułu 11.
//
// Uruchomienie (z kopii tego katalogu, obok której leży katalog resources/):
//
//	go run . -login "$LOGIN" > ../resources/sdk-$LOGIN.json
//
// Login bierze z flagi -login, potem ze zmiennej LOGIN. Bez obu wypisuje
// znacznik LOGIN, czyli dokładnie plik pliki/11-sdk-dashboard.json.
//
// Dashboard celowo łamie reguły `gcx dev lint run` (szukaj "LINT:"):
//   - panel-title-description: panele "ruch" i "bledy" nie mają opisu,
//   - uneditable-dashboard: SDK domyślnie ustawia editable: true.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/grafana/grafana-foundation-sdk/go/cog"
	dashboard "github.com/grafana/grafana-foundation-sdk/go/dashboardv2"
	"github.com/grafana/grafana-foundation-sdk/go/prometheus"
	"github.com/grafana/grafana-foundation-sdk/go/resource"
	"github.com/grafana/grafana-foundation-sdk/go/timeseries"
	"github.com/grafana/grafana-foundation-sdk/go/units"
)

// UID datasource'u Prometheus w Labie wspólnym. W v2 pole datasource.name to UID.
const promUID = "prometheus"

func promQuery(expr, legend string) cog.Builder[dashboard.DataQueryKind] {
	return prometheus.NewQueryV2Builder().
		Datasource(dashboard.NewDashboardv2DataQueryKindDatasourceBuilder().Name(promUID)).
		Expr(expr).
		LegendFormat(legend)
}

func panel(id float64, title string, viz *timeseries.VisualizationV2Builder, expr, legend string) *dashboard.PanelBuilder {
	return dashboard.NewPanelBuilder().
		Id(id).
		Title(title).
		Visualization(viz).
		Data(dashboard.NewQueryGroupBuilder().
			Target(dashboard.NewTargetBuilder().RefId("A").Query(promQuery(expr, legend))))
}

func main() {
	defLogin := os.Getenv("LOGIN")
	if defLogin == "" {
		defLogin = "LOGIN"
	}
	login := flag.String("login", defLogin, "login uczestnika: nazwa sdk-<login>, folder uczestnicy-<login>")
	flag.Parse()

	ruch := panel(1, "Ruch usług",
		timeseries.NewVisualizationV2Builder().Unit(units.RequestsPerSecond).Min(0),
		`sum by (service_name) (rate(traces_spanmetrics_calls_total{span_kind="SPAN_KIND_SERVER"}[$__rate_interval]))`,
		"{{service_name}}")
	// LINT: panel-title-description — dopisz .Description("...").

	bledy := panel(2, "Odsetek błędów",
		timeseries.NewVisualizationV2Builder().Unit(units.PercentUnit).Min(0),
		`sum by (service_name) (rate(traces_spanmetrics_calls_total{span_kind="SPAN_KIND_SERVER", status_code="STATUS_CODE_ERROR"}[$__rate_interval]))
/ sum by (service_name) (rate(traces_spanmetrics_calls_total{span_kind="SPAN_KIND_SERVER"}[$__rate_interval]))`,
		"{{service_name}}")
	// LINT: panel-title-description — dopisz .Description("...").

	p95 := panel(3, "Latencja p95",
		timeseries.NewVisualizationV2Builder().Unit(units.Seconds).Min(0),
		`histogram_quantile(0.95, sum by (le, service_name) (rate(traces_spanmetrics_latency_bucket{span_kind="SPAN_KIND_SERVER"}[$__rate_interval])))`,
		"{{service_name}}").
		Description("95. percentyl czasu obsługi spanów SERVER per usługa (span metrics z Tempo).")

	b := dashboard.NewDashboardBuilder("SDK — "+*login).
		Description("Dashboard v2 wygenerowany Foundation SDK (Go), moduł 11.").
		Tags([]string{"sdk", *login}).
		// LINT: uneditable-dashboard — SDK domyślnie daje editable: true; dopisz .Editable(false).
		TimeSettings(dashboard.NewTimeSettingsBuilder().From("now-1h").To("now").AutoRefresh("1m")).
		Panel("ruch", ruch).
		Panel("bledy", bledy).
		Panel("p95", p95).
		GridLayout(dashboard.Grid().
			Item(dashboard.GridItem("ruch").X(0).Y(0).Width(12).Height(8)).
			Item(dashboard.GridItem("bledy").X(12).Y(0).Width(12).Height(8)).
			Item(dashboard.GridItem("p95").X(0).Y(8).Width(24).Height(8)))

	// Manifest() opakowuje spec w zasób dashboard.grafana.app/v2; metadata
	// nadpisujemy, żeby dodać folder docelowy (adnotacja grafana.app/folder).
	m, err := dashboard.Manifest("sdk-"+*login, b).
		Metadata(resource.Named("sdk-" + *login).
			Annotations(map[string]string{"grafana.app/folder": "uczestnicy-" + *login})).
		Build()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	out, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(string(out))
}
