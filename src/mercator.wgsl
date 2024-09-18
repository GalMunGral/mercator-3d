const pi = radians(180);
const eps = 1e-9;
const R = 1f;


const SPHERE: u32 = 1 << 0;
const CYLINDER: u32 = 1 << 1;

const f = 1f;
const pixel_size = 0.0005;
const fov = radians(90);

const ambient = 0.4;
const diffuse = 0.6;

struct Uniforms {
  viewport_width: f32,
  viewport_height: f32,
  alpha: f32,
  beta: f32,
  eye: vec3f,
};

@group(0) @binding(0) var uSampler: sampler;
@group(0) @binding(1) var uTexture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> unif: Uniforms;

fn T(v: vec3f) -> vec3f {
  let R_xy = mat3x3f(
    cos(unif.beta), sin(unif.beta), 0,
    -sin(unif.beta), cos(unif.beta), 0,
    0, 0, 1
  );
  let R_yz = mat3x3f(
    1, 0, 0, 
    0, cos(unif.alpha), sin(unif.alpha),
    0, -sin(unif.alpha), cos(unif.alpha)
  );
  return R_xy * R_yz * v;
}

fn T_inv(v: vec3f) -> vec3f {
  let R_yz_inv = mat3x3f(
    1, 0, 0, 
    0, cos(-unif.alpha), sin(-unif.alpha),
    0, -sin(-unif.alpha), cos(-unif.alpha)
  );
  let R_xy_inv = mat3x3f(
    cos(-unif.beta), sin(-unif.beta), 0,
    -sin(-unif.beta), cos(-unif.beta), 0,
    0, 0, 1
  );
  return R_yz_inv * R_xy_inv * v;

}

fn hitSphere(p: vec3f, v: vec3f, incidence: u32) -> f32 {
  let t = dot(-p, v);
  let r = length(p + t * v);
  if r > R { return -1; }
  let tt = select(t, t - abs(t), bool(incidence & SPHERE));
  let d = sqrt(R * R - r * r);
  if tt < -d { return -1; }
  return select(t - d, t + d, tt < d);
}

fn sampleSphere(p: vec3f, l: vec3f) -> vec4f {
  let u = (atan2(p.y, p.x) + pi) / (2 * pi);
  let v = (pi / 2 -atan2(p.z, length(p.xy))) / pi;
  let phong = ambient + diffuse * dot(l, normalize(p));
  return textureSample(uTexture, uSampler, vec2f(u, v)) * phong;
}

fn hitCylinder(p: vec3f, v: vec3f, incidence: u32) -> f32 {
  var p0 = T_inv(p);
  let v0 = T_inv(v);
  let l = length(v0.xy);
  let t = dot(-p0.xy, v0.xy / l);
  let r = length(p0.xy + t * (v0.xy / l));
  if r > R { return -1; }
  let tt = select(t, t - abs(t), bool(incidence & CYLINDER));
  let d = sqrt(R * R - r * r);
  if tt < -d { return -1; }
  return select(t - d, t + d, tt < d) / l;
}

fn sampleCylinder(p: vec3f, l: vec3f) -> vec4f {
  let p0 = T_inv(p);
  let theta0 = atan2(p0.y, p0.x);
  let phi0 = 2 * atan(exp(p0.z / R)) - pi / 2;
  let r0 = vec3f(cos(phi0) * cos(theta0), cos(phi0) * sin(theta0), sin(phi0));
  let r = T(r0);
  let u = (atan2(r.y, r.x) + pi) / (2 * pi);
  let v = (pi / 2 - atan2(r.z, length(r.xy))) / pi;
  let n0 = normalize(vec3f(p0.xy, 0));
  let n = T(n0);
  let phong = ambient + diffuse * dot(l, n);
  let c = (textureSample(uTexture, uSampler, vec2f(u, v)) + 0.1) * phong;
  let a = clamp((length(unif.eye) / R - 2)/ 3, 0, 1);
  return select(vec4f(), vec4f(c.rgb, a), degrees(abs(phi0)) < 85);
}

@vertex
fn vsMain(@location(0) position: vec4f) -> @builtin(position) vec4f {
  return position;
}

@fragment
fn fsMain(@builtin(position) pos: vec4f) -> @location(0) vec4f {
  let forward = normalize(-unif.eye);
  let right = normalize(cross(forward, vec3f(0, 0, 1)));
  let up = cross(right, forward);

  let image_width = 2 * f * tan(fov / 2);
  let k = image_width / unif.viewport_width;
  let v = normalize(
    f * forward + 
    k * (pos.x - unif.viewport_width / 2) * right +
    k * (unif.viewport_height / 2 - pos.y) * up
  ); // ray direction

  let l = normalize(-forward + right + up); // light direction

  var C = vec3f(); // front-to-back accumulated color;
  var A = 0.0; // front-to-back accumulated opacity;

  var p = unif.eye; // current ray position;
  var incidence: u32 = 0; // whether `p` is on the surface of each object

  for (var i = 0; i < 6; i++) {
    var t = -1f;
    var c = vec4f();

    let t_sphere = hitSphere(p, v, incidence);
    let c_sphere = sampleSphere(p + t_sphere * v, l);
    if t_sphere > 0 && (t == -1f || t_sphere < t) {
      t = t_sphere;
      c = c_sphere;
    }

    let t_cylinder = hitCylinder(p, v, incidence);
    let c_cylinder = sampleCylinder(p + t_cylinder * v, l);
    if t_cylinder > 0 && (t == -1f || t_cylinder < t) {
      t = t_cylinder;
      c = c_cylinder;
    }

    if t > 0 {
      let sphere_hit = select(0u, SPHERE, abs(t - t_sphere) < eps);
      let cylinder_hit = select(0u, CYLINDER, abs(t - t_cylinder) < eps);
      incidence = sphere_hit | cylinder_hit;
      C += (1 - A) * c.a * c.rgb;
      A += (1 - A) * c.a;
      p += t * v;
    }
  }
  
  return vec4f(C, 1);
}