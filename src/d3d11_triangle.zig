const std = @import("std");
const win32 = @import("win32");
usingnamespace win32.zig;
usingnamespace win32.foundation;
usingnamespace win32.graphics.gdi;
usingnamespace win32.graphics.dxgi;
usingnamespace win32.graphics.direct3d11;
usingnamespace win32.graphics.hlsl;
usingnamespace win32.ui.windows_and_messaging;
usingnamespace win32.system.library_loader;
usingnamespace win32.system.diagnostics.debug;

pub fn Flag(comptime flag_type: type) type {
    return struct {
        pub fn from_list(flags: []flag_type) flag_type {
            var flag: u32 = 0;

            for (flags) |val| {
                flag |= @enumToInt(val);
            }

            return @intToEnum(flag_type, flag);
        }

        pub fn combine(flag_a: flag_type, flag_b: flag_type) flag_type {
            var flag_a_val: u32 = @enumToInt(flag_a);
            var flag_b_val: u32 = @enumToInt(flag_b);

            var flag_val = flag_a_val | flag_b_val;

            return @intToEnum(flag_type, flag_val);
        }

        pub fn asInt(int_type: type, flag: flag_type) type {
            return @intCast(int_type, @enumToInt(flag));
        }
    };
}

const Win32Errors = error{
    WindowClassRegistrationFailed,
    WindowClassDeRegistrationFailed,
    WindowCreationFailed,
    WindowDestructionFailed,
    InvalidWindowHandle,
};

const D3D11Errors = error{
    InvalidSampleCount,
    FailedToCreateDevice,
    FailedToObtainBufferFromSwapChain,
    FailedToCreateTexture2D,
    FailedToCreateRenderTargetView,
    FailedToCreateDepthStencilView,
    FailedToCreateRasterizerState,
    FailedToCreateSamplerState,
    FailedToCreateBlendState,
    FailedToCreateDepthStencilState,
    FailedToCompileShader,
    FailedToCreateVertexShader,
    FailedToCreatePixelShader,
    FailedToCreateComputeShader,
    FailedToCreateInputLayout,
    FailedToCreateBuffer,
};

const D3D11State = struct {
    device: *ID3D11Device = undefined,
    device_context: *ID3D11DeviceContext = undefined,

    swap_chain: *IDXGISwapChain = undefined,
    swap_chain_desc: DXGI_SWAP_CHAIN_DESC = undefined,

    render_target_buffer: *ID3D11Texture2D = undefined,
    render_target_view: *ID3D11RenderTargetView = undefined,
    depth_stencil_buffer: *ID3D11Texture2D = undefined,
    depth_stencil_view: *ID3D11DepthStencilView = undefined,

    input_layout: *ID3D11InputLayout = undefined,

    vertex_shader: *ID3D11VertexShader = undefined,
    pixel_shader: *ID3D11PixelShader = undefined,

    sampler_state: *ID3D11SamplerState = undefined,
    rasterizer_state: *ID3D11RasterizerState = undefined,
    blend_state: *ID3D11BlendState = undefined,
    depth_stencil_state: *ID3D11DepthStencilState = undefined,

    vertex_buffer: *ID3D11Buffer = undefined,

    sample_count: u32 = 1,
    width: u32 = 512,
    height: u32 = 512,
    valid_render_target: bool = false,
};

fn window_procedure(window_handle: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) callconv(.C) LRESULT {
    switch (message) {
        WM_DESTROY => {
            std.debug.print("Destroy Message\n", .{});
            PostQuitMessage(0);
        },
        WM_CLOSE => {
            std.debug.print("Close Message\n", .{});
        },
        WM_KEYDOWN => if (wparam == VK_ESCAPE) {
            std.debug.print("Escape Pressed Message\n", .{});
            PostQuitMessage(0);
        },
        else => {},
    }
    return DefWindowProcA(window_handle, message, wparam, lparam);
}

fn window_process_events() bool {
    var message = std.mem.zeroes(MSG);
    while (0 != PeekMessageA(&message, null, 0, 0, PM_REMOVE)) {
        if (WM_QUIT == message.message) {
            std.debug.print("Quit Message\n", .{});
            return false;
        } else {
            _ = TranslateMessage(&message);
            _ = DispatchMessageA(&message);
        }
    }
    return true;
}

fn window_create(name: [*:0]const u8, width: i32, height: i32) !HWND {
    var hInstance = @ptrCast(HINSTANCE, GetModuleHandleA(null));

    var win_class_name = "d3d11_window_zig";

    var win_class = WNDCLASSEXA{
        .cbSize = @sizeOf(WNDCLASSEXA),
        .style = CS_OWNDC,
        .lpfnWndProc = window_procedure,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hInstance,
        .hIcon = LoadIcon(hInstance, IDI_APPLICATION),
        .hCursor = LoadCursor(null, IDC_ARROW),
        .hbrBackground = @intToPtr(HBRUSH, @enumToInt(COLOR_WINDOW) + 1),
        .lpszMenuName = "dummy", // Impossible to pass null?
        .lpszClassName = win_class_name,
        .hIconSm = LoadIcon(hInstance, IDI_APPLICATION),
    };

    var hr = RegisterClassExA(&win_class);
    if (FAILED(hr)) {
        return Win32Errors.WindowClassRegistrationFailed;
    }

    var style_list = [_]WINDOW_STYLE{
        WS_CLIPSIBLINGS,
        WS_CLIPCHILDREN,
        WS_CAPTION,
        WS_SYSMENU,
        WS_MINIMIZEBOX,
        WS_SIZEBOX,
    };
    var style_ex_list = [_]WINDOW_EX_STYLE{ WS_EX_APPWINDOW, WS_EX_WINDOWEDGE };

    var win_style = Flag(WINDOW_STYLE).from_list(&style_list);
    var win_style_ex = Flag(WINDOW_EX_STYLE).from_list(&style_ex_list);

    var window_handle = CreateWindowExA(
        win_style_ex,
        win_class_name,
        name,
        win_style,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        width,
        height,
        null,
        null,
        win_class.hInstance,
        null,
    ) orelse return Win32Errors.WindowCreationFailed;

    return window_handle;
}

fn window_destroy(window_handle: HWND) !void {
    _ = DestroyWindow(window_handle);
    if (UnregisterClassA("d3d11_window_zig", GetModuleHandleA(null)) == 0) {
        return Win32Errors.WindowClassDeRegistrationFailed;
    }
    std.debug.print("Destoryed Window!\n", .{});
}

fn d3d11_init(window_handle: HWND, sample_count: u32) !D3D11State {
    if ((sample_count < 1) or (sample_count > 16) or
        (sample_count != 1 and sample_count % 2 != 0))
    {
        return D3D11Errors.InvalidSampleCount;
    }

    var window_rectangle: RECT = undefined;

    if (GetWindowRect(window_handle, &window_rectangle) == 0) {
        return Win32Errors.InvalidWindowHandle;
    }

    // create device and swap chain
    var state = D3D11State{};
    errdefer d3d11_term(&state);

    state.width = @intCast(u32, window_rectangle.right - window_rectangle.left);
    state.height = @intCast(u32, window_rectangle.bottom - window_rectangle.top);
    state.sample_count = sample_count;
    state.swap_chain_desc = DXGI_SWAP_CHAIN_DESC{
        .BufferDesc = DXGI_MODE_DESC{
            .Width = state.width,
            .Height = state.height,
            .Format = DXGI_FORMAT_B8G8R8A8_UNORM,
            .ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED,
            .Scaling = DXGI_MODE_SCALING_UNSPECIFIED,
            .RefreshRate = DXGI_RATIONAL{
                .Numerator = 60,
                .Denominator = 1,
            },
        },
        .SampleDesc = DXGI_SAMPLE_DESC{
            .Count = state.sample_count,
            .Quality = 0,
        },
        .BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT,
        .BufferCount = 1,
        .SwapEffect = DXGI_SWAP_EFFECT_DISCARD,
        .OutputWindow = window_handle,
        .Windowed = TRUE,
        .Flags = 0,
    };

    var create_flags = D3D11_CREATE_DEVICE_SINGLETHREADED;
    create_flags = Flag(D3D11_CREATE_DEVICE_FLAG).combine(create_flags, D3D11_CREATE_DEVICE_DEBUG);

    var feature_level: D3D_FEATURE_LEVEL = D3D_FEATURE_LEVEL_11_0;

    var hr = D3D11CreateDeviceAndSwapChain(null, // pAdapter (use default)
        D3D_DRIVER_TYPE_HARDWARE, // DriverType
        LoadLibraryA("dummy"), // Need a way to pass NULL here // Software
        create_flags, // Flags
        null, // pFeatureLevels
        0, // FeatureLevels
        D3D11_SDK_VERSION, // SDKVersion
        &state.swap_chain_desc, // pSwapChainDesc
        &state.swap_chain, // ppSwapChain
        &state.device, // ppDevice
        &feature_level, // pFeatureLevel
        &state.device_context); // ppImmediateContext

    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateDevice;
    }

    // Render targets - TODO(maciej): Inline this maybe? Seems like for this demo app we would like to have everything just as a big linear function
    try d3d11_create_default_render_target(&state);

    // Pipeline state
    var sampler_state_desc = std.mem.zeroes(D3D11_SAMPLER_DESC);
    sampler_state_desc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    sampler_state_desc.AddressU = D3D11_TEXTURE_ADDRESS_WRAP;
    sampler_state_desc.AddressV = D3D11_TEXTURE_ADDRESS_WRAP;
    sampler_state_desc.AddressW = D3D11_TEXTURE_ADDRESS_WRAP;
    sampler_state_desc.ComparisonFunc = D3D11_COMPARISON_NEVER;
    hr = state.device.ID3D11Device_CreateSamplerState(&sampler_state_desc, &state.sampler_state);
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateSamplerState;
    }

    var depth_stencil_state_desc = std.mem.zeroes(D3D11_DEPTH_STENCIL_DESC);
    depth_stencil_state_desc.DepthEnable = TRUE;
    depth_stencil_state_desc.DepthWriteMask = D3D11_DEPTH_WRITE_MASK_ALL;
    depth_stencil_state_desc.DepthFunc = D3D11_COMPARISON_LESS;
    hr = state.device.ID3D11Device_CreateDepthStencilState(&depth_stencil_state_desc, &state.depth_stencil_state);
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateDepthStencilState;
    }

    var rasterizer_state_desc = std.mem.zeroes(D3D11_RASTERIZER_DESC);
    rasterizer_state_desc.FrontCounterClockwise = TRUE;
    rasterizer_state_desc.FillMode = D3D11_FILL_SOLID;
    rasterizer_state_desc.CullMode = D3D11_CULL_BACK;

    hr = state.device.ID3D11Device_CreateRasterizerState(&rasterizer_state_desc, &state.rasterizer_state);
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateRasterizerState;
    }

    var blend_state_desc = std.mem.zeroes(D3D11_BLEND_DESC);
    blend_state_desc.AlphaToCoverageEnable = FALSE;
    blend_state_desc.IndependentBlendEnable = FALSE;
    blend_state_desc.RenderTarget[0] = .{
        .BlendEnable = TRUE,
        .SrcBlend = D3D11_BLEND_SRC_ALPHA,
        .DestBlend = D3D11_BLEND_INV_SRC_ALPHA,
        .BlendOp = D3D11_BLEND_OP_ADD,
        .SrcBlendAlpha = D3D11_BLEND_SRC_ALPHA,
        .DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA,
        .BlendOpAlpha = D3D11_BLEND_OP_ADD,
        .RenderTargetWriteMask = @enumToInt(D3D11_COLOR_WRITE_ENABLE_ALL),
    };

    hr = state.device.ID3D11Device_CreateBlendState(&blend_state_desc, &state.blend_state);
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateBlendState;
    }

    // Shaders
    const shdr_src =
        \\struct vs_in {
        \\   float4 pos: POS0;
        \\};
        \\struct vs_out {
        \\   float4 pos: SV_POSITION;
        \\};
        \\vs_out vs_main(vs_in input) {
        \\    vs_out output;
        \\    output.pos = input.pos;
        \\    return output;
        \\}
        \\
        \\float4 ps_main(vs_out input): SV_TARGET {
        \\    return float4(1.0, 0.0, 0.0, 1.0);
        \\}
    ;
    var vs_output: *ID3DBlob = undefined;
    var ps_output: *ID3DBlob = undefined;
    var errors: *ID3DBlob = undefined;
    var compile_flags: u32 = D3DCOMPILE_PACK_MATRIX_COLUMN_MAJOR | D3DCOMPILE_OPTIMIZATION_LEVEL3;
    _ = D3DCompile(shdr_src, shdr_src.len, null, null, null, "vs_main", "vs_5_0", compile_flags, 0, &vs_output, &errors);
    if (errors != undefined) {
        var err_str_ptr = @ptrCast([*]const u8, errors.ID3DBlob_GetBufferPointer());
        var err_str_size = errors.ID3DBlob_GetBufferSize();
        std.debug.print("Failed to compile shader!\n", .{});
        std.debug.print("{s}\n", .{err_str_ptr[0..err_str_size]});
        return D3D11Errors.FailedToCompileShader;
    }
    _ = D3DCompile(shdr_src, shdr_src.len, null, null, null, "ps_main", "ps_5_0", compile_flags, 0, &ps_output, &errors);
    if (errors != undefined) {
        var err_str_ptr = @ptrCast([*]const u8, errors.ID3DBlob_GetBufferPointer());
        var err_str_size = errors.ID3DBlob_GetBufferSize();
        std.debug.print("Failed to compile shader!\n", .{});
        std.debug.print("{s}\n", .{err_str_ptr[0..err_str_size]});
        return D3D11Errors.FailedToCompileShader;
    }

    hr = state.device.ID3D11Device_CreateVertexShader(
        @ptrCast([*]const u8, vs_output.ID3DBlob_GetBufferPointer()),
        vs_output.ID3DBlob_GetBufferSize(),
        null,
        &state.vertex_shader,
    );
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateVertexShader;
    }

    hr = state.device.ID3D11Device_CreatePixelShader(
        @ptrCast([*]const u8, ps_output.ID3DBlob_GetBufferPointer()),
        ps_output.ID3DBlob_GetBufferSize(),
        null,
        &state.pixel_shader,
    );
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreatePixelShader;
    }

    // Input layout
    var input_layout_desc = [1]D3D11_INPUT_ELEMENT_DESC{
        .{
            .SemanticName = "POS",
            .SemanticIndex = 0,
            .Format = DXGI_FORMAT_R32G32B32A32_FLOAT,
            .AlignedByteOffset = 0,
            .InputSlot = 0,
            .InputSlotClass = D3D11_INPUT_PER_VERTEX_DATA,
            .InstanceDataStepRate = 0,
        },
    };
    hr = state.device.ID3D11Device_CreateInputLayout(
        &input_layout_desc,
        input_layout_desc.len,
        @ptrCast([*]const u8, vs_output.ID3DBlob_GetBufferPointer()),
        vs_output.ID3DBlob_GetBufferSize(),
        &state.input_layout,
    );
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateInputLayout;
    }
    _ = vs_output.IUnknown_Release();
    _ = ps_output.IUnknown_Release();

    var positions = [12]f32{
        0.0, 0.0, 0.0, 1.0,
        1.0, 0.0, 0.0, 1.0,
        0.0, 1.0, 0.0, 1.0,
    };
    var vertex_buffer_desc = D3D11_BUFFER_DESC{
        .ByteWidth = positions.len * @sizeOf(f32),
        .Usage = D3D11_USAGE_DEFAULT,
        .BindFlags = @enumToInt(D3D11_BIND_VERTEX_BUFFER),
        .CPUAccessFlags = 0,
        .MiscFlags = 0,
        .StructureByteStride = 0,
    };
    var vertex_buffer_data = D3D11_SUBRESOURCE_DATA{
        .pSysMem = &positions,
        .SysMemPitch = 0,
        .SysMemSlicePitch = 0,
    };

    hr = state.device.ID3D11Device_CreateBuffer(
        &vertex_buffer_desc,
        &vertex_buffer_data,
        &state.vertex_buffer,
    );
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateBuffer;
    }

    return state;
}

fn d3d11_term(state: *D3D11State) void {
    if (state.device == undefined) {
        return;
    }

    d3d11_destroy_default_render_target(state);

    _ = state.rasterizer_state.IUnknown_Release();
    _ = state.depth_stencil_state.IUnknown_Release();
    _ = state.sampler_state.IUnknown_Release();
    _ = state.blend_state.IUnknown_Release();

    state.rasterizer_state = undefined;
    state.depth_stencil_state = undefined;
    state.sampler_state = undefined;
    state.blend_state = undefined;

    _ = state.vertex_shader.IUnknown_Release();
    _ = state.pixel_shader.IUnknown_Release();

    state.vertex_shader = undefined;
    state.pixel_shader = undefined;

    _ = state.swap_chain.IUnknown_Release();
    _ = state.device_context.IUnknown_Release();
    _ = state.device.IUnknown_Release();

    state.device = undefined;
    state.device_context = undefined;
    state.swap_chain = undefined;

    std.debug.print("Terminated D3D11!\n", .{});
}

fn d3d11_create_default_render_target(state: *D3D11State) !void {
    var hr: HRESULT = undefined;

    hr = state.swap_chain.IDXGISwapChain_GetBuffer(0, IID_ID3D11Texture2D, @ptrCast(
        **c_void,
        &state.render_target_buffer,
    ));
    if (FAILED(hr)) {
        return D3D11Errors.FailedToObtainBufferFromSwapChain;
    }

    hr = state.device.ID3D11Device_CreateRenderTargetView(
        @ptrCast(*ID3D11Resource, state.render_target_buffer),
        null,
        &state.render_target_view,
    );

    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateRenderTargetView;
    }

    var depth_stencil_desc = D3D11_TEXTURE2D_DESC{
        .Width = state.width,
        .Height = state.height,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = DXGI_FORMAT_D24_UNORM_S8_UINT,
        .SampleDesc = state.swap_chain_desc.SampleDesc,
        .Usage = D3D11_USAGE_DEFAULT,
        .BindFlags = D3D11_BIND_DEPTH_STENCIL,
        .CPUAccessFlags = @intToEnum(D3D11_CPU_ACCESS_FLAG, 0),
        .MiscFlags = @intToEnum(D3D11_RESOURCE_MISC_FLAG, 0),
    };

    hr = state.device.ID3D11Device_CreateTexture2D(&depth_stencil_desc, null, &state.depth_stencil_buffer);
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateTexture2D;
    }

    // NOTE(maciej): What is the best way to do partial initialization in zig?
    // The issue here is that we want to set Flags to nothing, but we cannot
    var depth_stencil_view_desc = std.mem.zeroes(D3D11_DEPTH_STENCIL_VIEW_DESC);
    depth_stencil_view_desc.Format = depth_stencil_desc.Format;
    depth_stencil_view_desc.ViewDimension = if (state.sample_count > 1) D3D11_DSV_DIMENSION_TEXTURE2DMS else D3D11_DSV_DIMENSION_TEXTURE2D;

    hr = state.device.ID3D11Device_CreateDepthStencilView(
        @ptrCast(*ID3D11Resource, state.depth_stencil_buffer),
        &depth_stencil_view_desc,
        &state.depth_stencil_view,
    );
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateDepthStencilView;
    }
    state.valid_render_target = true;
}

fn d3d11_update_default_render_target(state: *D3D11State) void {
    if (state.valid_render_target) {
        d3d11_destroy_default_render_target(state);
        _ = state.swap_chain.IDXGISwapChain_ResizeBuffers(1, state.width, state.height, DXGI_FORMAT_B8G8R8A8_UNORM, 0);
        d3d11_create_default_render_target(state) catch unreachable;
    }
}

fn d3d11_destroy_default_render_target(state: *D3D11State) void {
    _ = state.render_target_buffer.IUnknown_Release();
    _ = state.render_target_view.IUnknown_Release();
    _ = state.depth_stencil_buffer.IUnknown_Release();
    _ = state.depth_stencil_view.IUnknown_Release();
    state.render_target_buffer = undefined;
    state.render_target_view = undefined;
    state.depth_stencil_buffer = undefined;
    state.depth_stencil_view = undefined;

    state.valid_render_target = false;
}

fn d3d11_present(window_handle: HWND, state: *D3D11State) void {
    // TODO(maciej): How to deal with device reset?
    _ = state.swap_chain.IDXGISwapChain_Present(1, 0);
    // handle window resizing
    var window_rectangle: RECT = undefined;
    if (GetClientRect(window_handle, &window_rectangle) != 0) {
        var cur_width = @intCast(u32, window_rectangle.right - window_rectangle.left);
        var cur_height = @intCast(u32, window_rectangle.bottom - window_rectangle.top);
        if (((cur_width > 0) and (cur_width != state.width)) or
            ((cur_height > 0) and (cur_height != state.height)))
        {
            state.width = cur_width;
            state.height = cur_height;
            d3d11_update_default_render_target(state);
        }
    }
}

pub fn main() !void {
    var window_handle: HWND = try window_create("D3D11Window", 512, 512);
    defer window_destroy(window_handle) catch unreachable;
    var state: D3D11State = try d3d11_init(window_handle, 1);
    defer d3d11_term(&state);

    _ = ShowWindow(window_handle, SW_SHOWDEFAULT);
    _ = UpdateWindow(window_handle);

    var runtime_zero: usize = 0;
    while (window_process_events()) {
        // Begins a render pass
        var window_rectangle: RECT = undefined;
        _ = GetClientRect(window_handle, &window_rectangle);

        var rtvs = [_]*ID3D11RenderTargetView{state.render_target_view};
        state.device_context.ID3D11DeviceContext_OMSetRenderTargets(1, &rtvs, state.depth_stencil_view);

        var viewport = std.mem.zeroes(D3D11_VIEWPORT);
        viewport.Width = @intToFloat(f32, state.width);
        viewport.Height = @intToFloat(f32, state.height);
        viewport.MaxDepth = 1.0;
        var viewports = [_]D3D11_VIEWPORT{viewport};
        var rects = [_]RECT{window_rectangle};
        state.device_context.ID3D11DeviceContext_RSSetViewports(viewports.len, &viewports);
        state.device_context.ID3D11DeviceContext_RSSetScissorRects(rects.len, &rects);
        state.device_context.ID3D11DeviceContext_RSSetState(state.rasterizer_state);

        var clear_color = [_]f32{ 1.0, 0.5, 0.0, 1.0 };
        state.device_context.ID3D11DeviceContext_ClearRenderTargetView(rtvs[0], &clear_color[0]);
        var depth_stencil_flags = @intCast(u32, @enumToInt(D3D11_CLEAR_DEPTH)) | @intCast(u32, @enumToInt(D3D11_CLEAR_STENCIL));
        state.device_context.ID3D11DeviceContext_ClearDepthStencilView(state.depth_stencil_view, depth_stencil_flags, 1.0, 0);

        var blend_color = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
        state.device_context.ID3D11DeviceContext_OMSetDepthStencilState(state.depth_stencil_state, 0);
        state.device_context.ID3D11DeviceContext_OMSetBlendState(state.blend_state, &blend_color[0], 0xFFFFFFFF);

        state.device_context.ID3D11DeviceContext_IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        state.device_context.ID3D11DeviceContext_IASetInputLayout(state.input_layout);
        var buffers = [_]*ID3D11Buffer{state.vertex_buffer};
        var strides = [_]u32{4 * @sizeOf(f32)};
        var offsets = [_]u32{0};

        state.device_context.ID3D11DeviceContext_IASetVertexBuffers(0, buffers.len, &buffers, &strides, &offsets);
        state.device_context.ID3D11DeviceContext_VSSetShader(state.vertex_shader, null, 0);
        state.device_context.ID3D11DeviceContext_PSSetShader(state.pixel_shader, null, 0);

        state.device_context.ID3D11DeviceContext_Draw(3, 0);

        d3d11_present(window_handle, &state);
    }
}