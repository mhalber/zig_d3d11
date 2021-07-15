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
usingnamespace win32.system.com;

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
    FailedToCreateDXGIDevice,
    FailedToGetDXGIAdapter,
    FailedToGetDXGIFactory2,
    FailedToCreateD3D11Device,
    FailedToCreateD3D11DeviceContext,
    FailedToCreateD3D11Device1,
    FailedToCreateD3D11DeviceContext1,
    FailedToCreateD3D11DeviceAndSwapchain,
    FailedToCreateSwapchain,
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
    device: *ID3D11Device1 = undefined,
    device_context: *ID3D11DeviceContext1 = undefined,
    swap_chain: *IDXGISwapChain1 = undefined,
    swap_chain_desc: DXGI_SWAP_CHAIN_DESC1 = undefined,

    render_target_buffer: *ID3D11Texture2D = undefined,
    render_target_view: *ID3D11RenderTargetView = undefined,
    depth_stencil_buffer: *ID3D11Texture2D = undefined,
    depth_stencil_view: *ID3D11DepthStencilView = undefined,

    vertex_shader: *ID3D11VertexShader = undefined,
    pixel_shader: *ID3D11PixelShader = undefined,

    sampler_state: *ID3D11SamplerState = undefined,
    rasterizer_state: *ID3D11RasterizerState1 = undefined,
    blend_state: *ID3D11BlendState1 = undefined,
    depth_stencil_state: *ID3D11DepthStencilState = undefined,

    input_layout: *ID3D11InputLayout = undefined,
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

    var window_class_name = "d3d11_window_zig";
    var window_class_style = [_]WNDCLASS_STYLES{
        CS_HREDRAW,
        CS_VREDRAW,
        CS_OWNDC,
    };

    var window_class = std.mem.zeroes(WNDCLASSEXA);
    window_class.cbSize = @sizeOf(WNDCLASSEXA);
    window_class.lpfnWndProc = window_procedure;
    window_class.hCursor = LoadCursor(null, IDC_ARROW);
    window_class.hIcon = LoadIcon(null, IDI_APPLICATION);
    window_class.lpszClassName = window_class_name;
    window_class.style = Flag(WNDCLASS_STYLES).from_list(&window_class_style);

    var hr = RegisterClassExA(&window_class);
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

    var window_style = Flag(WINDOW_STYLE).from_list(&style_list);
    var window_style_ex = Flag(WINDOW_EX_STYLE).from_list(&style_ex_list);

    var window_handle = CreateWindowExA(
        window_style_ex,
        window_class_name,
        name,
        window_style,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        width,
        height,
        null,
        null,
        window_class.hInstance,
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

    // Create base device to request approperiate device later
    var feature_levels = [_]D3D_FEATURE_LEVEL{D3D_FEATURE_LEVEL_11_1};
    var base_device: *ID3D11Device = undefined;
    var base_device_context: *ID3D11DeviceContext = undefined;
    var device_flags: D3D11_CREATE_DEVICE_FLAG = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    device_flags = Flag(D3D11_CREATE_DEVICE_FLAG).combine(device_flags, D3D11_CREATE_DEVICE_SINGLETHREADED);
    device_flags = Flag(D3D11_CREATE_DEVICE_FLAG).combine(device_flags, D3D11_CREATE_DEVICE_DEBUG);

    var hr = D3D11CreateDevice(
        null,
        D3D_DRIVER_TYPE_HARDWARE,
        LoadLibraryA("dummy"), // This should be an optional pointer?
        device_flags,
        &feature_levels,
        feature_levels.len,
        D3D11_SDK_VERSION,
        &base_device,
        null,
        &base_device_context,
    );
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateD3D11Device;
    }

    // Create ID3D11Device1
    hr = base_device.IUnknown_QueryInterface(IID_ID3D11Device1, @ptrCast(**c_void, &state.device));
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateD3D11Device1;
    }

    // Create ID3D11DeviceContext1
    hr = base_device_context.IUnknown_QueryInterface(IID_ID3D11DeviceContext1, @ptrCast(**c_void, &state.device_context));
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateD3D11DeviceContext1;
    }

    // Get the DXGI objects in order to get the access to swap chain creation calls
    var dxgi_device: *IDXGIDevice1 = undefined;
    var dxgi_adapter: *IDXGIAdapter = undefined;
    var dxgi_factory: *IDXGIFactory2 = undefined;
    hr = state.device.IUnknown_QueryInterface(IID_IDXGIDevice1, @ptrCast(**c_void, &dxgi_device));
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateDXGIDevice;
    }

    hr = dxgi_device.IDXGIDevice_GetAdapter(&dxgi_adapter);
    if (FAILED(hr)) {
        return D3D11Errors.FailedToGetDXGIAdapter;
    }

    hr = dxgi_adapter.IDXGIObject_GetParent(IID_IDXGIFactory2, @ptrCast(**c_void, &dxgi_factory));
    if (FAILED(hr)) {
        return D3D11Errors.FailedToGetDXGIFactory2;
    }

    state.width = @intCast(u32, window_rectangle.right - window_rectangle.left);
    state.height = @intCast(u32, window_rectangle.bottom - window_rectangle.top);
    state.sample_count = sample_count;
    state.swap_chain_desc = DXGI_SWAP_CHAIN_DESC1{
        .Width = 0,
        .Height = 0,
        .Format = DXGI_FORMAT_B8G8R8A8_UNORM,
        .Stereo = FALSE,
        .SampleDesc = DXGI_SAMPLE_DESC{
            .Count = state.sample_count,
            .Quality = 0,
        },
        .BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT,
        .BufferCount = 1,
        .Scaling = DXGI_SCALING_STRETCH,
        .SwapEffect = DXGI_SWAP_EFFECT_DISCARD,
        .AlphaMode = DXGI_ALPHA_MODE_UNSPECIFIED,
        .Flags = 0,
    };

    hr = dxgi_factory.IDXGIFactory2_CreateSwapChainForHwnd(
        @ptrCast(*IUnknown, state.device),
        window_handle,
        &state.swap_chain_desc,
        null,
        null,
        &state.swap_chain,
    );
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateSwapchain;
    }

    // Cleanup
    _ = base_device.IUnknown_Release();
    _ = base_device_context.IUnknown_Release();
    _ = dxgi_device.IUnknown_Release();
    _ = dxgi_adapter.IUnknown_Release();
    _ = dxgi_factory.IUnknown_Release();

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

    var rasterizer_state_desc = std.mem.zeroes(D3D11_RASTERIZER_DESC1);
    rasterizer_state_desc.FrontCounterClockwise = TRUE;
    rasterizer_state_desc.FillMode = D3D11_FILL_SOLID;
    rasterizer_state_desc.CullMode = D3D11_CULL_BACK;

    hr = state.device.ID3D11Device1_CreateRasterizerState1(&rasterizer_state_desc, &state.rasterizer_state);
    if (FAILED(hr)) {
        return D3D11Errors.FailedToCreateRasterizerState;
    }

    var blend_state_desc = std.mem.zeroes(D3D11_BLEND_DESC1);
    blend_state_desc.AlphaToCoverageEnable = FALSE;
    blend_state_desc.IndependentBlendEnable = FALSE;
    blend_state_desc.RenderTarget[0] = .{
        .BlendEnable = TRUE,
        .LogicOpEnable = FALSE,
        .SrcBlend = D3D11_BLEND_SRC_ALPHA,
        .DestBlend = D3D11_BLEND_INV_SRC_ALPHA,
        .BlendOp = D3D11_BLEND_OP_ADD,
        .SrcBlendAlpha = D3D11_BLEND_SRC_ALPHA,
        .DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA,
        .BlendOpAlpha = D3D11_BLEND_OP_ADD,
        .RenderTargetWriteMask = @enumToInt(D3D11_COLOR_WRITE_ENABLE_ALL),
        .LogicOp = D3D11_LOGIC_OP_CLEAR,
    };

    hr = state.device.ID3D11Device1_CreateBlendState1(&blend_state_desc, &state.blend_state);
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

    _ = state.input_layout.IUnknown_Release();
    _ = state.vertex_buffer.IUnknown_Release();

    _ = state.rasterizer_state.IUnknown_Release();
    _ = state.depth_stencil_state.IUnknown_Release();
    _ = state.sampler_state.IUnknown_Release();
    _ = state.blend_state.IUnknown_Release();

    state.sampler_state = undefined;
    state.rasterizer_state = undefined;
    state.blend_state = undefined;
    state.depth_stencil_state = undefined;

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

    var depth_stencil_desc: D3D11_TEXTURE2D_DESC = undefined;
    state.render_target_buffer.ID3D11Texture2D_GetDesc(&depth_stencil_desc);
    depth_stencil_desc.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
    depth_stencil_desc.BindFlags = D3D11_BIND_DEPTH_STENCIL;

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
        state.device_context.ID3D11DeviceContext_RSSetState(@ptrCast(*ID3D11RasterizerState, state.rasterizer_state));

        var clear_color = [_]f32{ 1.0, 0.5, 0.0, 1.0 };
        state.device_context.ID3D11DeviceContext_ClearRenderTargetView(rtvs[0], &clear_color[0]);
        var depth_stencil_flags = @intCast(u32, @enumToInt(D3D11_CLEAR_DEPTH)) | @intCast(u32, @enumToInt(D3D11_CLEAR_STENCIL));
        state.device_context.ID3D11DeviceContext_ClearDepthStencilView(state.depth_stencil_view, depth_stencil_flags, 1.0, 0);

        var blend_color = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
        state.device_context.ID3D11DeviceContext_OMSetDepthStencilState(state.depth_stencil_state, 0);
        state.device_context.ID3D11DeviceContext_OMSetBlendState(@ptrCast(*ID3D11BlendState, state.blend_state), &blend_color[0], 0xFFFFFFFF);

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
