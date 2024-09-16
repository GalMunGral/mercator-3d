const pi = radians(180);

@vertex
fn vsMain(@location(0) position: vec4f) -> @builtin(position) vec4f {
  return position;
}

const R = 10f;

struct Uniforms {
  eye: vec3f,
  viewport_width: f32,
  viewport_height: f32,
};

@group(0) @binding(0) var uSampler: sampler;
@group(0) @binding(1) var uTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> uniforms: Uniforms;

fn hitSphere(p: vec3f, v: vec3f) -> f32 {
  let t = dot(-p, v);
  let r = length(p + t * v);
  if r > R { return -1; }
  let d = sqrt(R * R - r * r);
  if t < -d { return -1; };
  return select(t - d, t + d, t < d);
}

fn hitCylinder(p: vec3f, v: vec3f) -> f32 {
  let u = v / length(v.xy);
  let t = dot(-p.xy, u.xy);
  let r = length(p.xy + t * u.xy);
  if r > R { return -1; }
  let d = sqrt(R * R - r * r);
  if t < -d { return -1; };
  return select(t - d, t + d, t < d);
}

const f = 1f;

@fragment
fn fsMain(@builtin(position) pos: vec4f) -> @location(0) vec4f {
const pixel_size = 0.0005;

  let forward = normalize(-uniforms.eye);
  let right = normalize(cross(forward, vec3f(0, 0, 1)));
  let up = cross(right, forward);

  const fov = radians(60);
  let scale = (2 * f * tan(fov / 2)) / uniforms.viewport_width;
  let v = normalize(
    f * forward + 
    (pos.x - uniforms.viewport_width / 2) * scale * right +
    -(pos.y - uniforms.viewport_height / 2) * scale * up
  );

  var C = vec3f();
  var a = 0.0;
  
  let light = normalize(-2 * R * forward + R * right + R * up);
  let p = uniforms.eye;
  const ambient = 0.2;
  const diffuse = 0.8;

  let a_c = clamp((length(uniforms.eye.xy) / R - 4) / 4, 0, 1);
  let t_c = hitCylinder(p, v);
  let q_c = p + t_c * v;
  let u_c = (atan2(q_c.y, q_c.x) + pi) / (2 * pi);
  let v_c = 1 - 2 * atan(exp(q_c.z / R)) / pi; // check this
  let phong_c = ambient + diffuse * dot(light, normalize(vec3f(q_c.xy, 0))); // check this
  let c_c = textureSample(uTexture, uSampler, vec2f(u_c, v_c)) * phong_c;
  if t_c >= 0 {
    C += (1 - a) * a_c * c_c.rgb;
    a += (1 - a) * a_c;
  }

  const a_s = 1.0;
  let t_s = hitSphere(p, v);
  let q_s = p + t_s * v;
  let u_s = (atan2(q_s.y, q_s.x) + pi) / (2 * pi);
  let v_s = (-atan2(q_s.z, length(q_s.xy)) + pi / 2) / pi;
  let phong_s = ambient + diffuse * dot(light, normalize(q_s));
  let c_s = textureSample(uTexture, uSampler, vec2f(u_s, v_s)) * phong_s;
  if t_s >= 0 {
    C += (1 - a) * a_s * c_s.rgb;
    a += (1 - a) * a_s;
  }
  
  return vec4f(C, 1);
}