// Runs once after Storage and application migrations, including on existing volumes.
const base = 'http://storage:5000';
const headers = { Authorization: `Bearer ${process.env.SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' };
const bucket = { id: 'pomodoist-shared', name: 'pomodoist-shared', public: false, file_size_limit: 20000000 };
const existing = await fetch(`${base}/bucket/${bucket.id}`, { headers });
if (existing.ok) {
  const result = await fetch(`${base}/bucket/${bucket.id}`, { method: 'PUT', headers, body: JSON.stringify(bucket) });
  if (!result.ok) throw new Error('Private file bucket configuration failed');
} else {
  if (existing.status !== 400 && existing.status !== 404) throw new Error('Private file bucket lookup failed');
  const result = await fetch(`${base}/bucket`, { method: 'POST', headers, body: JSON.stringify(bucket) });
  if (!result.ok) throw new Error('Private file bucket creation failed');
}
