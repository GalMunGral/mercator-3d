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

const SPHERE: u32 = 1 << 0;
const CYLINDER: u32 = 1 << 1;
const CYLINDER_2: u32 = 1 << 2;

fn hitSphere(_p: vec3f, v: vec3f, object: u32) -> f32 {
  var p = _p;
  let t = dot(-p, v);
  let r = length(p + t * v);
  if r > R {
    return -1;
  }
  let t_test = select(t, t - abs(t), bool(object & SPHERE));
  let d = sqrt(R * R - r * r);
  if t_test < -d {
    return -1;
  };
  return select(t - d, t + d, t_test < d);
}

fn hitCylinder(_p: vec3f, u: vec3f, object: u32) -> f32 {
  var p = _p;
  let t = dot(-p.xy, u.xy);
  let r = length(p.xy + t * u.xy);
  if r > R {
    return -1;
  }
  let t_test = select(t, t - abs(t), bool(object & CYLINDER));
  let d = sqrt(R * R - r * r);
  if t_test < -d {
    return -1;
  };
  return select(t - d, t + d, t_test < d);
}

fn hitCylinder_2(_p: vec3f, w: vec3f, object: u32) -> f32 {
  var p = _p;
  let t = dot(-p.yz, w.yz);
  let r = length(p.yz + t * w.yz);
  if r > R {
    return -1;
  }
  let t_test = select(t, t - abs(t), bool(object & CYLINDER_2));
  let d = sqrt(R * R - r * r);
  if t_test < -d {
    return -1;
  };
  return select(t - d, t + d, t_test < d);
}

const f = 1f;
const ambient = 0.2;
const diffuse = 0.8;

fn sampleSphere(q: vec3f, l: vec3f) -> vec4f {
  const a = 1;
  let u = (atan2(q.y, q.x) + pi) / (2 * pi);
  let v = (-atan2(q.z, length(q.xy)) + pi / 2) / pi;
  let phong = ambient + diffuse * abs(dot(l, normalize(q)));
  let c = textureSample(uTexture, uSampler, vec2f(u, v)) * phong;
  return vec4f(c.rgb, a);
}

fn sampleCylinder(q: vec3f, l: vec3f) -> vec4f {
  let a = clamp((length(uniforms.eye.xy) / R - 1) / 10, 0, 1);
  let u = (atan2(q.y, q.x) + pi) / (2 * pi);
  let v = 1 - 2 * atan(exp(q.z / R)) / pi; // check this
  let phong = ambient + diffuse * abs(dot(l, normalize(vec3f(q.xy, 0)))); // check this
  let c = textureSample(uTexture, uSampler, vec2f(u, v)) * phong;
  return vec4f(c.rgb, a);
}

fn sampleCylinder_2(q: vec3f, l: vec3f) -> vec4f {
  let a = clamp((length(uniforms.eye.xy) / R - 1) / 10, 0, 1);
  let theta = atan2(q.z, q.y);
  let phi = 2 * atan(exp(q.x / R)) - pi / 2; // check this
  let phong = ambient + diffuse * abs(dot(l, normalize(vec3f(q.yz, 0)))); // check this
  let x = sin(phi);
  let y = cos(phi) * cos(theta);
  let z = cos(phi) * sin(theta);
  let u = atan2(y, x) / (2 * pi) + 0.5;
  let v = 0.5 - atan2(z, sqrt(x * x + y * y)) / pi;
  let c = textureSample(uTexture, uSampler, vec2f(u, v)) * phong;
  return vec4f(c.rgb, a);
}

const eps = 1e-9;

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
  let u = v / length(v.xy);
  let w = v / length(v.yz);

  let l = normalize(-2 * R * forward + R * right + R * up);

  var p = uniforms.eye;
  var C = vec3f();
  var a = 0.0;
  var object: u32 = 0;

  for (var i = 0; i < 6; i++) {
    var t = -1f;
    var c = vec4f();
    let t1 = hitSphere(p, v, object);
    let c1 = sampleSphere(p + t1 * v, l);
    let t2 = hitCylinder(p, u, object);
    let c2 = sampleCylinder(p + t2 * u, l);
    let t3 = hitCylinder_2(p, w, object);
    let c3 = sampleCylinder_2(p + t3 * w, l);
    if t1 > 0 && (t < 0 || t1 < t) {
      t = t1;
      c = c1;
    }
    if t2 > 0 && (t == -1 || t2 < t) {
      t = t2;
      c = c2;
    }
    // if t3 > 0 && (t == -1 || t3 < t) {
    //   t = t3;
    //   c = c3;
    // }
    if t > 0 {
      if abs(t - t1) < eps {
        object |= SPHERE;
      } else {
        object &= ~SPHERE;
      }
      if abs(t - t2) < eps {
        object |= CYLINDER;
      } else {
        object &= ~CYLINDER;
      }
      if abs(t - t3) < eps {
        object |= CYLINDER_2;
      } else {
        object &= ~CYLINDER_2;
      }
      C += (1 - a) * c.a * c.rgb;
      a += (1 - a) * c.a;
      p += t * v;
    }
  }

  
  return vec4f(C, 1);
}