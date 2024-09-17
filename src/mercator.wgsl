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
  alpha: f32,
  beta: f32,
};

@group(0) @binding(0) var uSampler: sampler;
@group(0) @binding(1) var uTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> uniforms: Uniforms;

const SPHERE: u32 = 1 << 0;
const CYLINDER: u32 = 1 << 1;

fn forward(v: vec3f) -> vec3f {
  let R1 = mat3x3f(
    1, 0, 0, 
    0, cos(uniforms.alpha), sin(uniforms.alpha),
    0, -sin(uniforms.alpha), cos(uniforms.alpha)
  );
  let R2 = mat3x3f(
    cos(uniforms.beta), sin(uniforms.beta), 0,
    -sin(uniforms.beta), cos(uniforms.beta), 0,
    0, 0, 1
  );
  return R2 * R1 * v;
}

fn backward(v: vec3f) -> vec3f {
  let R1_inv = mat3x3f(
    1, 0, 0, 
    0, cos(-uniforms.alpha), sin(-uniforms.alpha),
    0, -sin(-uniforms.alpha), cos(-uniforms.alpha)
  );
  let R2_inv = mat3x3f(
    cos(-uniforms.beta), sin(-uniforms.beta), 0,
    -sin(-uniforms.beta), cos(-uniforms.beta), 0,
    0, 0, 1
  );
  return R1_inv * R2_inv * v;

}

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

fn hitCylinder(_p: vec3f, _v: vec3f, object: u32) -> f32 {
  var p = backward(_p);
  let v = backward(_v);
  let u = v / length(v.xy);
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
  return select(t - d, t + d, t_test < d) / length(v.xy);
}

const f = 1f;
const ambient = 0.5;
const diffuse = 0.5;

fn sampleSphere(q: vec3f, l: vec3f) -> vec4f {
  const a = 1;
  let u = (atan2(q.y, q.x) + pi) / (2 * pi);
  let v = (-atan2(q.z, length(q.xy)) + pi / 2) / pi;
  let phong = ambient + diffuse * dot(l, normalize(q));
  let c = textureSample(uTexture, uSampler, vec2f(u, v)) * phong;
  return vec4f(c.rgb, a);
}

fn sampleCylinder(_q: vec3f, l: vec3f) -> vec4f {
  let q = backward(_q);
  let a = clamp((length(uniforms.eye) - 2 * R)/ (5 * R), 0, 1);
  let theta = atan2(q.y, q.x);
  let phi = 2 * atan(exp(q.z / R)) - pi / 2;
  let r = forward(vec3f(cos(phi) * cos(theta), cos(phi) * sin(theta), sin(phi)));
  let u = (atan2(r.y, r.x) + pi) / (2 * pi);
  let v = (pi / 2 - atan2(r.z, length(r.xy))) / pi;
  let phong = ambient + diffuse * dot(l, normalize(vec3f(_q.xy, 0))); // check this
  let c = (textureSample(uTexture, uSampler, vec2f(u, v)) + vec4f(0.1)) * phong;
  if degrees(abs(phi)) > 85 { return vec4f(); }
  return vec4f(c.rgb, a);
}


const eps = 1e-9;

@fragment
fn fsMain(@builtin(position) pos: vec4f) -> @location(0) vec4f {
const pixel_size = 0.0005;

  let forward = normalize(-uniforms.eye);
  let right = normalize(cross(forward, vec3f(0, 0, 1)));
  let up = cross(right, forward);

  const fov = radians(90);
  let scale = (2 * f * tan(fov / 2)) / uniforms.viewport_width;
  let v = normalize(
    f * forward + 
    (pos.x - uniforms.viewport_width / 2) * scale * right +
    -(pos.y - uniforms.viewport_height / 2) * scale * up
  );

  let l = normalize(normalize(uniforms.eye) + 0.5 * right + 0.5 * up);

  var p = uniforms.eye;
  var C = vec3f();
  var a = 0.0;
  var object: u32 = 0;

  for (var i = 0; i < 6; i++) {
    var t = -1f;
    var c = vec4f();
    let t1 = hitSphere(p, v, object);
    let c1 = sampleSphere(p + t1 * v, l);
    let t2 = hitCylinder(p, v, object);
    let c2 = sampleCylinder(p + t2 * v, l);
    if t1 > 0 && (t < 0 || t1 < t) {
      t = t1;
      c = c1;
    }
    if t2 > 0 && (t == -1 || t2 < t) {
      t = t2;
      c = c2;
    }
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
      C += (1 - a) * c.a * c.rgb;
      a += (1 - a) * c.a;
      p += t * v;
    }
  }

  
  return vec4f(C, 1);
}