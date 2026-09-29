import { FilterBar, useQuery } from '@blp/dashboard-runtime'
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ComposedChart,
  Legend,
  Line,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

const C = {
  blue: '#2563eb',
  green: '#16a34a',
  amber: '#f59e0b',
  red: '#dc2626',
  slate: '#64748b',
  violet: '#7c3aed',
}

const WEEKDAYS: Record<string, string> = {
  '1': 'Dom',
  '2': 'Lun',
  '3': 'Mar',
  '4': 'Mié',
  '5': 'Jue',
  '6': 'Vie',
  '7': 'Sáb',
}

const CATEGORY_LABEL: Record<string, string> = {
  on_time: 'En hora / adelantado',
  minor: 'Leve (≤30 min)',
  moderate: 'Moderada (30-60 min)',
  severe: 'Severa (>60 min)',
}

const CATEGORY_COLOR: Record<string, string> = {
  on_time: C.green,
  minor: C.amber,
  moderate: '#ea580c',
  severe: C.red,
}

const card: React.CSSProperties = {
  background: '#fff',
  border: '1px solid #e2e8f0',
  borderRadius: 12,
  padding: 16,
  boxShadow: '0 1px 2px rgba(15,23,42,.05)',
}

const grid: React.CSSProperties = {
  display: 'grid',
  gap: 16,
  gridTemplateColumns: 'repeat(auto-fit, minmax(360px, 1fr))',
}

const num = (v: any) => (v === null || v === undefined ? '—' : Number(v).toLocaleString('es-AR'))
const one = (v: any) => (v === null || v === undefined ? '—' : Number(v).toFixed(1))

function Section({ title, subtitle, children }: { title: string; subtitle?: string; children: React.ReactNode }) {
  return (
    <div style={card}>
      <div style={{ marginBottom: 12 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: '#0f172a' }}>{title}</div>
        {subtitle ? <div style={{ fontSize: 12, color: C.slate }}>{subtitle}</div> : null}
      </div>
      {children}
    </div>
  )
}

function Kpi({ label, value, hint, accent }: { label: string; value: string; hint?: string; accent?: string }) {
  return (
    <div style={{ ...card, padding: 14 }}>
      <div style={{ fontSize: 12, color: C.slate, textTransform: 'uppercase', letterSpacing: '.04em' }}>{label}</div>
      <div style={{ fontSize: 24, fontWeight: 700, color: accent ?? '#0f172a', marginTop: 4 }}>{value}</div>
      {hint ? <div style={{ fontSize: 12, color: C.slate, marginTop: 2 }}>{hint}</div> : null}
    </div>
  )
}

function Table({ columns, rows, format }: { columns: string[]; rows: any[]; format?: Record<string, (v: any) => string> }) {
  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
        <thead>
          <tr>
            {columns.map((c) => (
              <th
                key={c}
                style={{ textAlign: 'left', padding: '6px 8px', borderBottom: '1px solid #e2e8f0', color: C.slate, fontWeight: 600, whiteSpace: 'nowrap' }}
              >
                {c}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} style={{ background: i % 2 ? '#f8fafc' : 'transparent' }}>
              {columns.map((c) => (
                <td key={c} style={{ padding: '6px 8px', borderBottom: '1px solid #f1f5f9', whiteSpace: 'nowrap' }}>
                  {format && format[c] ? format[c](r[c]) : String(r[c] ?? '—')}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function ChartState({ loading, error, empty, children }: any) {
  if (loading) return <div style={{ color: C.slate, fontSize: 13 }}>Cargando…</div>
  if (error) return <div style={{ color: C.red, fontSize: 13 }}>Error: {error}</div>
  if (empty) return <div style={{ color: C.slate, fontSize: 13 }}>Sin datos para los filtros seleccionados.</div>
  return children
}

export default function AerolineasArgentina() {
  const kpis = useQuery('kpis')
  const daily = useQuery('daily_trend')
  const airlines = useQuery('airline_perf')
  const airports = useQuery('airport_perf')
  const dist = useQuery('delay_distribution')
  const hourly = useQuery('hourly_profile')
  const weekday = useQuery('weekday_profile')
  const routes = useQuery('top_routes')
  const gates = useQuery('gate_perf')
  const terminals = useQuery('terminal_perf')

  const k = kpis.data?.rows?.[0] ?? {}
  const dailyRows = (daily.data?.rows ?? []).map((r: any) => ({ ...r, label: String(r.flight_date).slice(5) }))
  const airlineRows = airlines.data?.rows ?? []
  const airportRows = airports.data?.rows ?? []
  const distRows = (dist.data?.rows ?? []).map((r: any) => ({ ...r, label: CATEGORY_LABEL[r.delay_category] ?? r.delay_category }))
  const hourlyRows = (hourly.data?.rows ?? []).map((r: any) => ({ ...r, label: `${String(r.scheduled_hour).padStart(2, '0')}h` }))
  const weekdayRows = (weekday.data?.rows ?? []).map((r: any) => ({ ...r, label: WEEKDAYS[String(r.day_of_week)] ?? String(r.day_of_week) }))
  const routeRows = routes.data?.rows ?? []
  const gateRows = gates.data?.rows ?? []
  const terminalRows = terminals.data?.rows ?? []

  return (
    <div style={{ fontFamily: 'system-ui, -apple-system, Segoe UI, sans-serif', padding: 16, background: '#f8fafc' }}>
      <div style={{ marginBottom: 16 }}>
        <h2 style={{ margin: 0, fontSize: 20, color: '#0f172a' }}>Aerolíneas Argentina · Operación y Puntualidad</h2>
        <div style={{ fontSize: 13, color: C.slate, marginTop: 4 }}>
          Puntualidad, demoras y volumen de vuelos de los aeropuertos argentinos (AEP, EZE, COR, MDZ, BRC, IGR, SLA, NQN).
          Una demora cuenta como tal a partir de 15 minutos sobre el horario programado.
        </div>
      </div>

      <div style={{ ...card, marginBottom: 16 }}>
        <FilterBar />
      </div>

      <div style={{ ...grid, gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', marginBottom: 16 }}>
        <Kpi label="Vuelos" value={num(k.total_flights)} hint={`Datos: ${k.first_date ?? '—'} → ${k.last_date ?? '—'}`} />
        <Kpi label="Puntualidad" value={`${one(k.on_time_pct)}%`} accent={C.green} hint={`${num(k.on_time_flights)} en hora o adelantados`} />
        <Kpi label="Demora media" value={`${one(k.avg_delay_minutes)} min`} accent={C.amber} hint="Vuelos completados" />
        <Kpi label="Demorados" value={num(k.delayed_flights)} accent="#ea580c" hint="≥15 min de atraso" />
        <Kpi label="Demora pesada" value={`${one(k.heavy_delay_pct)}%`} accent={C.red} hint="Más de 45 min" />
        <Kpi label="Cancelaciones" value={`${one(k.cancellation_pct)}%`} accent={C.red} hint={`${num(k.cancelled_flights)} vuelos`} />
        <Kpi label="Vuelos únicos" value={num(k.unique_flights)} hint="Según filtros actuales" />
      </div>

      <div style={{ ...grid, marginBottom: 16 }}>
        <Section title="Evolución diaria" subtitle="Volumen de vuelos vs. demora media y puntualidad">
          <ChartState loading={daily.loading} error={daily.error} empty={!dailyRows.length}>
            <ResponsiveContainer width="100%" height={280}>
              <ComposedChart data={dailyRows} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                <XAxis dataKey="label" tick={{ fontSize: 11 }} minTickGap={24} />
                <YAxis yAxisId="left" tick={{ fontSize: 11 }} />
                <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 11 }} />
                <Tooltip />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar yAxisId="left" dataKey="total_flights" name="Vuelos" fill={C.blue} opacity={0.35} />
                <Line yAxisId="right" type="monotone" dataKey="avg_delay_minutes" name="Demora media (min)" stroke={C.red} dot={false} strokeWidth={2} />
                <Line yAxisId="right" type="monotone" dataKey="on_time_pct" name="Puntualidad (%)" stroke={C.green} dot={false} strokeWidth={2} />
              </ComposedChart>
            </ResponsiveContainer>
          </ChartState>
        </Section>

        <Section title="Distribución de demoras" subtitle="Cuántos vuelos caen en cada categoría">
          <ChartState loading={dist.loading} error={dist.error} empty={!distRows.length}>
            <ResponsiveContainer width="100%" height={280}>
              <PieChart>
                <Pie data={distRows} dataKey="total_flights" nameKey="label" innerRadius={60} outerRadius={100} paddingAngle={2}>
                  {distRows.map((r: any, i: number) => (
                    <Cell key={i} fill={CATEGORY_COLOR[r.delay_category] ?? C.slate} />
                  ))}
                </Pie>
                <Tooltip />
                <Legend wrapperStyle={{ fontSize: 12 }} />
              </PieChart>
            </ResponsiveContainer>
            <Table
              columns={['label', 'total_flights', 'pct', 'avg_delay_minutes']}
              rows={distRows}
              format={{ total_flights: num, pct: (v) => `${one(v)}%`, avg_delay_minutes: (v) => `${one(v)} min` }}
            />
          </ChartState>
        </Section>
      </div>

      <div style={{ ...grid, marginBottom: 16 }}>
        <Section title="Puntualidad por aerolínea" subtitle="Top 20 por volumen (mínimo 20 vuelos)">
          <ChartState loading={airlines.loading} error={airlines.error} empty={!airlineRows.length}>
            <ResponsiveContainer width="100%" height={Math.max(260, airlineRows.length * 26)}>
              <BarChart data={airlineRows} layout="vertical" margin={{ top: 4, right: 24, left: 90, bottom: 4 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                <XAxis type="number" tick={{ fontSize: 11 }} />
                <YAxis type="category" dataKey="airline_name" tick={{ fontSize: 10 }} width={140} />
                <Tooltip />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="on_time_pct" name="Puntualidad (%)" fill={C.green} />
                <Bar dataKey="cancellation_pct" name="Cancelación (%)" fill={C.red} />
              </BarChart>
            </ResponsiveContainer>
            <Table
              columns={['airline_name', 'total_flights', 'avg_delay_minutes', 'on_time_pct', 'heavy_delay_pct', 'cancellation_pct']}
              rows={airlineRows}
              format={{ total_flights: num, avg_delay_minutes: (v) => `${one(v)}`, on_time_pct: (v) => `${one(v)}%`, heavy_delay_pct: (v) => `${one(v)}%`, cancellation_pct: (v) => `${one(v)}%` }}
            />
          </ChartState>
        </Section>

        <Section title="Actividad por aeropuerto" subtitle="Salidas y arribos con demora media por sentido">
          <ChartState loading={airports.loading} error={airports.error} empty={!airportRows.length}>
            <ResponsiveContainer width="100%" height={280}>
              <ComposedChart data={airportRows} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                <XAxis dataKey="airport_code" tick={{ fontSize: 11 }} />
                <YAxis yAxisId="left" tick={{ fontSize: 11 }} />
                <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 11 }} />
                <Tooltip />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar yAxisId="left" dataKey="departures" name="Salidas" fill={C.blue} />
                <Bar yAxisId="left" dataKey="arrivals" name="Arribos" fill={C.violet} />
                <Line yAxisId="right" type="monotone" dataKey="avg_departure_delay" name="Demora salidas (min)" stroke={C.amber} strokeWidth={2} />
                <Line yAxisId="right" type="monotone" dataKey="avg_arrival_delay" name="Demora arribos (min)" stroke={C.red} strokeWidth={2} />
              </ComposedChart>
            </ResponsiveContainer>
            <Table
              columns={['airport_code', 'departures', 'arrivals', 'avg_departure_delay', 'avg_arrival_delay', 'on_time_pct', 'cancellation_pct']}
              rows={airportRows}
              format={{ departures: num, arrivals: num, avg_departure_delay: one, avg_arrival_delay: one, on_time_pct: (v) => `${one(v)}%`, cancellation_pct: (v) => `${one(v)}%` }}
            />
          </ChartState>
        </Section>
      </div>

      <div style={{ ...grid, marginBottom: 16 }}>
        <Section title="Perfil horario" subtitle="Vuelos programados por hora y puntualidad del día">
          <ChartState loading={hourly.loading} error={hourly.error} empty={!hourlyRows.length}>
            <ResponsiveContainer width="100%" height={280}>
              <ComposedChart data={hourlyRows} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                <XAxis dataKey="label" tick={{ fontSize: 10 }} interval={1} />
                <YAxis yAxisId="left" tick={{ fontSize: 11 }} />
                <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 11 }} />
                <Tooltip />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar yAxisId="left" dataKey="total_flights" name="Vuelos" fill={C.blue} opacity={0.4} />
                <Line yAxisId="right" type="monotone" dataKey="delayed_pct" name="Demorados (%)" stroke={C.amber} strokeWidth={2} />
                <Line yAxisId="right" type="monotone" dataKey="avg_delay_minutes" name="Demora media (min)" stroke={C.red} strokeWidth={2} />
              </ComposedChart>
            </ResponsiveContainer>
          </ChartState>
        </Section>

        <Section title="Patrón semanal" subtitle="Puntualidad y volumen por día de la semana">
          <ChartState loading={weekday.loading} error={weekday.error} empty={!weekdayRows.length}>
            <ResponsiveContainer width="100%" height={280}>
              <ComposedChart data={weekdayRows} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                <XAxis dataKey="label" tick={{ fontSize: 11 }} />
                <YAxis yAxisId="left" tick={{ fontSize: 11 }} />
                <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 11 }} />
                <Tooltip />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar yAxisId="left" dataKey="total_flights" name="Vuelos" fill={C.violet} opacity={0.4} />
                <Line yAxisId="right" type="monotone" dataKey="on_time_pct" name="Puntualidad (%)" stroke={C.green} strokeWidth={2} />
                <Line yAxisId="right" type="monotone" dataKey="avg_delay_minutes" name="Demora media (min)" stroke={C.red} strokeWidth={2} />
              </ComposedChart>
            </ResponsiveContainer>
          </ChartState>
        </Section>
      </div>

      <div style={{ ...grid, marginBottom: 16 }}>
        <Section title="Rutas más operadas" subtitle="Origen → destino por aerolínea (mínimo 5 vuelos completados)">
          <ChartState loading={routes.loading} error={routes.error} empty={!routeRows.length}>
            <Table
              columns={['origin_airport_code', 'destination_airport_code', 'airline_name', 'total_flights', 'avg_delay_minutes', 'on_time_pct', 'cancellation_pct']}
              rows={routeRows}
              format={{ total_flights: num, avg_delay_minutes: one, on_time_pct: (v) => `${one(v)}%`, cancellation_pct: (v) => `${one(v)}%` }}
            />
          </ChartState>
        </Section>

        <Section title="Puertas más usadas" subtitle="Top 15 por volumen, con puntualidad">
          <ChartState loading={gates.loading} error={gates.error} empty={!gateRows.length}>
            <Table
              columns={['gate', 'total_flights', 'avg_delay_minutes', 'on_time_pct', 'max_delay_minutes']}
              rows={gateRows}
              format={{ total_flights: num, avg_delay_minutes: one, on_time_pct: (v) => `${one(v)}%`, max_delay_minutes: num }}
            />
          </ChartState>
        </Section>
      </div>

      <Section title="Terminales" subtitle="Volumen y puntualidad por terminal">
        <ChartState loading={terminals.loading} error={terminals.error} empty={!terminalRows.length}>
          <Table
            columns={['terminal', 'total_flights', 'avg_delay_minutes', 'on_time_pct']}
            rows={terminalRows}
            format={{ total_flights: num, avg_delay_minutes: one, on_time_pct: (v) => `${one(v)}%` }}
          />
        </ChartState>
      </Section>
    </div>
  )
}
