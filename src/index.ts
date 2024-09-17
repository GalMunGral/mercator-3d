import shaderSrc from "./mercator.wgsl";
import imageUrl from "./test.jpg";

export type TypedArray = Float32Array | Uint16Array;
export type TypedArrayConstructor = new (a: ArrayBuffer) => TypedArray;

export function createBuffer(
  device: GPUDevice,
  data: TypedArray,
  usage: GPUTextureUsageFlags
): GPUBuffer {
  const buffer = device.createBuffer({
    size: data.byteLength,
    usage,
    mappedAtCreation: true,
  });
  const dst = new (data.constructor as TypedArrayConstructor)(
    buffer.getMappedRange()
  );
  dst.set(data);
  buffer.unmap();
  return buffer;
}

async function main() {
  const width = window.innerWidth * devicePixelRatio;
  const height = window.innerHeight * devicePixelRatio;
  const canvas = document.querySelector("canvas#main") as HTMLCanvasElement;
  canvas.width = width;
  canvas.height = height;
  canvas.style.width = width / devicePixelRatio + "px";
  canvas.style.height = height / devicePixelRatio + "px";

  const sceneBuffer: number[] = [];

  const context: GPUCanvasContext = canvas.getContext("webgpu")!;

  const adapter = (await navigator.gpu.requestAdapter())!;
  const device = (await adapter.requestDevice())!;

  const presentationFormat = navigator.gpu.getPreferredCanvasFormat();
  context.configure({
    device,
    format: presentationFormat,
    alphaMode: "premultiplied",
  });

  const sampleCount = 1;

  const renderTarget = device.createTexture({
    size: [canvas.width, canvas.height],
    format: presentationFormat,
    sampleCount,
    usage: GPUTextureUsage.RENDER_ATTACHMENT,
  });

  const depthTexture = device.createTexture({
    size: [canvas.width, canvas.height],
    format: "depth24plus",
    sampleCount,
    usage: GPUTextureUsage.RENDER_ATTACHMENT,
  });

  const positions = new Float32Array([-1, 1, 1, 1, 1, -1, -1, -1]);
  const positionBuffer = createBuffer(device, positions, GPUBufferUsage.VERTEX);

  const indices = new Uint16Array([0, 3, 1, 2, 1, 3]);
  const indicesBuffer = createBuffer(device, indices, GPUBufferUsage.INDEX);

  const shaderModule = device.createShaderModule({ code: shaderSrc });
  const pipeline = device.createRenderPipeline({
    label: "newton-vg",
    layout: "auto",
    vertex: {
      module: shaderModule,
      buffers: [
        {
          arrayStride: 2 * 4,
          attributes: [{ shaderLocation: 0, offset: 0, format: "float32x2" }],
        },
      ],
    },
    fragment: {
      module: shaderModule,
      targets: [{ format: presentationFormat }],
    },
    primitive: {
      topology: "triangle-list",
      cullMode: "back",
    },
    depthStencil: {
      depthWriteEnabled: true,
      depthCompare: "less",
      format: "depth24plus",
    },
    multisample: {
      count: sampleCount,
    },
  });

  const sampler = device.createSampler({
    magFilter: "linear",
    minFilter: "linear",
  });

  const texture = device.createTexture({
    size: [5400, 2700],
    format: "rgba8unorm",
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  });

  const uniformValues = new Float32Array(8);
  const uniformBuffer = device.createBuffer({
    size: Math.max(32, uniformValues.byteLength),
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });

  const bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [
      { binding: 0, resource: sampler },
      { binding: 1, resource: texture.createView() },
      { binding: 2, resource: { buffer: uniformBuffer } },
    ],
  });

  const res = await fetch(imageUrl);
  const blob = await res.blob();
  const bitmap = await createImageBitmap(blob);

  device.queue.copyExternalImageToTexture(
    { source: bitmap },
    { texture },
    { width: 5400, height: 2700 }
  );

  const keydown: Record<string, boolean> = {};

  window.onkeydown = (e) => {
    keydown[e.key] = true;
  };
  window.onkeyup = (e) => {
    keydown[e.key] = false;
  };

  const R = 10;
  let theta = 0;
  let prev = Infinity;
  let d = 5 * R;
  let h = 2 * R;
  let alpha = 0;
  let beta = 0;

  function render(t: number) {
    const dt = 0.001 * Math.max(0, t - prev);
    prev = t;
    if (keydown["w"]) {
      d -= R * 5 * dt;
    }
    if (keydown["s"]) {
      d += R * 5 * dt;
    }
    if (keydown["ArrowUp"]) {
      alpha += dt;
    }
    if (keydown["ArrowDown"]) {
      alpha -= dt;
    }
    if (keydown["ArrowLeft"]) {
      beta += dt;
    }
    if (keydown["ArrowRight"]) {
      beta -= dt;
    }
    if (Object.values(keydown).every((x) => !x)) {
      theta += 0.5 * dt;
    }
    d = Math.min(10 * R, Math.max(0.1, d));
    uniformValues.set([
      d * Math.cos(theta),
      d * Math.sin(theta),
      h,
      width,
      height,
      alpha,
      beta,
    ]);
    device.queue.writeBuffer(uniformBuffer, 0, uniformValues);

    const commandEncoder = device.createCommandEncoder();
    const passEncoder = commandEncoder.beginRenderPass({
      colorAttachments: [
        {
          // view: renderTarget.createView(),
          // resolveTarget: context.getCurrentTexture().createView(),
          view: context.getCurrentTexture().createView(),
          clearValue: { r: 0, g: 0, b: 0, a: 0 },
          loadOp: "clear",
          storeOp: "store",
        },
      ],
      depthStencilAttachment: {
        view: depthTexture.createView(),
        depthClearValue: 1,
        depthLoadOp: "clear",
        depthStoreOp: "store",
      },
    });
    passEncoder.setPipeline(pipeline);
    passEncoder.setBindGroup(0, bindGroup);
    passEncoder.setVertexBuffer(0, positionBuffer);
    passEncoder.setIndexBuffer(indicesBuffer, "uint16");
    passEncoder.drawIndexed(indices.length);
    passEncoder.end();
    device.queue.submit([commandEncoder.finish()]);
    requestAnimationFrame(render);
  }
  requestAnimationFrame(render);
}

main();
