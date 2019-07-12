def _package_impl(ctx):
    output_filename = "{}-{}.tgz".format(ctx.attr.chart_name, ctx.attr.chart_version)
    output_tgz = ctx.actions.declare_file(output_filename)
    outputs = [output_tgz]
    ctx.actions.run(
        inputs = [] + ctx.files.srcs + ctx.files.tars,
        outputs = outputs,
        tools = [ctx.executable._helm],
        progress_message = "Generating Helm package archive {}".format(output_filename),
        executable = ctx.executable._script,
        env = {
            "PACKAGE_DIR": ctx.attr.package_dir,
            # TODO(f0rmiga): Figure out a way of working with paths that contain spaces.
            "TARS": " ".join([f.path for f in ctx.files.tars]),
            "HELM": ctx.executable._helm.path,
            "CHART_VERSION": ctx.attr.chart_version,
            "APP_VERSION": ctx.attr.app_version,
            "OUTPUT_FILENAME": output_filename,
            "OUTPUT_TGZ": output_tgz.path,
        },
    )
    return [DefaultInfo(files = depset(outputs))]

_package = rule(
    implementation = _package_impl,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
        ),
        "tars": attr.label_list(),
        "package_dir": attr.string(
            mandatory = True,
        ),
        "chart_name": attr.string(
            mandatory = True,
        ),
        "chart_version": attr.string(
            mandatory = True,
        ),
        "app_version": attr.string(
            mandatory = True,
        ),
        "_helm": attr.label(
            allow_single_file = True,
            cfg = "host",
            default = "@helm//:helm",
            executable = True,
        ),
        "_script": attr.label(
            allow_single_file = True,
            cfg = "host",
            default = "//rules/helm:package.sh",
            executable = True,
        ),
    },
)

def package(**kwargs):
    _package(
        package_dir = native.package_name(),
        **kwargs
    )

PackageInfo = provider(
    fields=[
        "chart_name",
        "chart_version",
    ],
)

def _package_info_aspect_impl(target, ctx):
    return [PackageInfo(
        chart_name = ctx.rule.attr.chart_name,
        chart_version = ctx.rule.attr.chart_version,
    )]

package_info_aspect = aspect(
    implementation = _package_info_aspect_impl,
    attr_aspects = [
        "chart_name",
        "chart_version",
    ],
)

def _template_impl(ctx):
    chart_package_chart_name = ctx.attr.chart_package[PackageInfo].chart_name
    chart_package_chart_version = ctx.attr.chart_package[PackageInfo].chart_version
    output_filename = "{}_{}-install_{}-namespace_{}.yaml".format(
        chart_package_chart_name,
        chart_package_chart_version,
        ctx.attr.install_name,
        ctx.attr.namespace,
    )
    output_yaml = ctx.actions.declare_file(output_filename)
    outputs = [output_yaml]
    arguments = ["--set={}={}".format(key, value)
                    for (key, value) in ctx.attr.set_values.items()]
    ctx.actions.run(
        inputs = [ctx.file.chart_package],
        outputs = outputs,
        tools = [ctx.executable._helm],
        progress_message = "Rendering Helm package archive {chart_package} to {output}".format(
            chart_package = chart_package_chart_name,
            output = output_filename,
        ),
        executable = ctx.executable._script,
        env = {
            "HELM": ctx.executable._helm.path,
            "INSTALL_NAME": ctx.attr.install_name,
            "NAMESPACE": ctx.attr.namespace,
            "CHART_PACKAGE": ctx.file.chart_package.path,
            "OUTPUT_YAML": output_yaml.path,
        },
        arguments = arguments,
    )
    return [DefaultInfo(files = depset(outputs))]

template = rule(
    implementation = _template_impl,
    attrs = {
        "set_values": attr.string_dict(
            default = {},
        ),
        "install_name": attr.string(
            mandatory = True,
        ),
        "namespace": attr.string(
            mandatory = True,
        ),
        "chart_package": attr.label(
            mandatory = True,
            allow_single_file = True,
            aspects = [package_info_aspect],
        ),
        "_helm": attr.label(
            allow_single_file = True,
            cfg = "host",
            default = "@helm//:helm",
            executable = True,
        ),
        "_script": attr.label(
            allow_single_file = True,
            cfg = "host",
            default = "//rules/helm:template.sh",
            executable = True,
        ),
    },
)

def _init_impl(ctx):
    executable = ctx.actions.declare_file(ctx.attr.name)
    contents = """
        set -o errexit
        export KUBECTL="{kubectl}"
        export HELM="{helm}"
        export SERVICE_ACCOUNT="{service_account}"
        "{script}"
    """.format(
        kubectl = ctx.executable._kubectl.path,
        helm = ctx.executable._helm.path,
        service_account = ctx.attr.service_account,
        script = ctx.executable._script.path,
    )
    ctx.actions.write(executable, contents, is_executable = True)
    runfiles = [
        ctx.executable._kubectl,
        ctx.executable._helm,
        ctx.executable._script,
    ]
    return [DefaultInfo(
        executable = executable,
        runfiles = ctx.runfiles(files = runfiles),
    )]

init = rule(
    implementation = _init_impl,
    attrs = {
        "service_account": attr.string(
            default = "tiller",
        ),
        "_kubectl": attr.label(
            allow_single_file = True,
            cfg = "host",
            default = "@kubectl//:kubectl",
            executable = True,
        ),
        "_helm": attr.label(
            allow_single_file = True,
            cfg = "host",
            default = "@helm//:helm",
            executable = True,
        ),
        "_script": attr.label(
            allow_single_file = True,
            cfg = "host",
            default = "//rules/helm:init.sh",
            executable = True,
        ),
    },
    executable = True,
)